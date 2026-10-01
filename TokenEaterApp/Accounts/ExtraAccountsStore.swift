import Foundation
import Combine
import Security
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "ExtraAccountsStore")

/// A Claude Code login other than the default one. Claude Code keeps each
/// `CLAUDE_CONFIG_DIR` login in its own Keychain item whose service name
/// starts with "Claude Code-credentials", so the service name is the
/// account's identity here.
struct ExtraClaudeAccount: Codable, Identifiable, Equatable {
    var id: String { service }
    let service: String
    /// Short name shown in the menu bar. Falls back to the email's local part.
    var label: String
    var enabled: Bool
}

/// The latest usage read for one extra account.
struct ExtraAccountUsage: Equatable {
    var email: String?
    var fiveHour: Double?
    var sevenDay: Double?
    var fiveHourResetsAt: Date?
    var sevenDayResetsAt: Date?
    var error: String?
    var updatedAt: Date
}

/// Tracks usage for every extra Claude Code login, alongside the main
/// account `UsageStore` handles. Read-only like the rest of the app: it reads
/// each Keychain item through `SecurityCLIReader` and never writes or
/// refreshes a token.
@MainActor
final class ExtraAccountsStore: ObservableObject {
    static let primaryService = "Claude Code-credentials"
    private static let defaultsKey = "extraClaudeAccounts"

    @Published private(set) var accounts: [ExtraClaudeAccount] = []
    @Published private(set) var usage: [String: ExtraAccountUsage] = [:]
    @Published private(set) var isRefreshing = false

    /// A full `UsageStore` for the first enabled extra account. The Claude
    /// Work mode swaps it in for the main store, so every popover cell, the
    /// plan badge and pacing read that account with no new UI.
    @Published private(set) var workUsageStore: UsageStore?

    var proxyConfig: ProxyConfig?
    /// Applies the app's settings (pacing, thresholds, refresh interval) to a
    /// freshly built work store and starts its auto-refresh.
    var configureWorkStore: ((UsageStore) -> Void)?

    private let apiClient: APIClientProtocol
    private let defaults: UserDefaults
    private var timer: Timer?
    private var workService: String?
    private var workCancellable: AnyCancellable?

    init(apiClient: APIClientProtocol = APIClient(), defaults: UserDefaults = .standard) {
        self.apiClient = apiClient
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([ExtraClaudeAccount].self, from: data) {
            accounts = saved
        }
    }

    var enabledAccounts: [ExtraClaudeAccount] { accounts.filter(\.enabled) }

    // MARK: - Lifecycle

    func start(interval: TimeInterval) {
        discover()
        rebuildWorkStore()
        Task { await refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(interval, 60), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: - Discovery

    /// Adds any Keychain item named "Claude Code-credentials-…" not already
    /// known. Asks for attributes only, never the data, so it cannot trigger
    /// the Keychain access prompt.
    func discover() {
        let known = Set(accounts.map(\.service))
        let found = Self.listExtraServices().filter { !known.contains($0) }
        guard !found.isEmpty else { return }
        logger.info("Discovered \(found.count, privacy: .public) extra Claude login(s)")
        let next = accounts.count
        accounts += found.enumerated().map { offset, service in
            ExtraClaudeAccount(service: service, label: "C\(next + offset + 2)", enabled: true)
        }
        save()
        rebuildWorkStore()
    }

    private static func listExtraServices() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        let services = items.compactMap { $0[kSecAttrService as String] as? String }
            .filter { $0.hasPrefix(primaryService + "-") }
        return Array(Set(services)).sorted()
    }

    // MARK: - Editing

    func setLabel(_ label: String, for service: String) {
        guard let index = accounts.firstIndex(where: { $0.service == service }) else { return }
        accounts[index].label = String(label.prefix(6))
        save()
        objectWillChange.send()
    }

    func setEnabled(_ enabled: Bool, for service: String) {
        guard let index = accounts.firstIndex(where: { $0.service == service }) else { return }
        accounts[index].enabled = enabled
        save()
        rebuildWorkStore()
        if enabled { Task { await refresh() } }
    }

    func remove(_ service: String) {
        accounts.removeAll { $0.service == service }
        usage[service] = nil
        save()
        rebuildWorkStore()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: - Refresh

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for account in enabledAccounts {
            if account.service == workService {
                // Its UsageStore polls usage; only the email is needed here.
                if usage[account.service]?.email == nil {
                    usage[account.service] = await fetchEmailOnly(account)
                }
                continue
            }
            usage[account.service] = await fetch(account)
        }
    }

    private func fetch(_ account: ExtraClaudeAccount) async -> ExtraAccountUsage {
        var result = usage[account.service] ?? ExtraAccountUsage(updatedAt: Date())
        result.updatedAt = Date()

        let service = account.service
        let read = await Task.detached { SecurityCLIReader(service: service).read() }.value
        guard let token = read.token else {
            result.error = read.failure == .accessDenied
                ? String(localized: "extraAccounts.error.denied")
                : String(localized: "extraAccounts.error.noLogin")
            return result
        }

        do {
            let response = try await apiClient.fetchUsage(token: token, proxyConfig: proxyConfig)
            result.fiveHour = response.fiveHour?.utilization
            result.sevenDay = response.sevenDay?.utilization
            result.fiveHourResetsAt = response.fiveHour?.resetsAtDate
            result.sevenDayResetsAt = response.sevenDay?.resetsAtDate
            result.error = nil
        } catch APIError.tokenExpired {
            result.error = String(localized: "extraAccounts.error.expired")
        } catch APIError.rateLimited {
            result.error = String(localized: "extraAccounts.error.rateLimited")
        } catch {
            result.error = error.localizedDescription
        }

        if result.email == nil, result.error == nil,
           let profile = try? await apiClient.fetchProfile(token: token, proxyConfig: proxyConfig) {
            result.email = profile.account.email
        }
        return result
    }

    private func fetchEmailOnly(_ account: ExtraClaudeAccount) async -> ExtraAccountUsage {
        var result = usage[account.service] ?? ExtraAccountUsage(updatedAt: Date())
        let service = account.service
        let read = await Task.detached { SecurityCLIReader(service: service).read() }.value
        if let token = read.token,
           let profile = try? await apiClient.fetchProfile(token: token, proxyConfig: proxyConfig) {
            result.email = profile.account.email
        }
        return result
    }

    // MARK: - Work account store

    /// Keeps `workUsageStore` pointed at the first enabled extra account,
    /// building a new one only when that account changes.
    private func rebuildWorkStore() {
        let target = enabledAccounts.first?.service
        guard target != workService else { return }
        workUsageStore?.stopAutoRefresh()
        workCancellable = nil
        workService = target
        guard let service = target else {
            workUsageStore = nil
            return
        }

        let suffix = service.replacingOccurrences(of: Self.primaryService + "-", with: "")
            .filter { $0.isLetter || $0.isNumber }
        let sharedFile = SharedFileService(fileName: "shared-\(suffix).json")
        let tokenProvider = TokenProvider(
            securityCLIReader: SecurityCLIReader(service: service),
            credentialsFileReader: CredentialsFileReader(filePath: ""),
            configReader: NoClaudeDesktopConfig(),
            keychainReader: { _ in nil }
        )
        let store = UsageStore(
            repository: UsageRepository(apiClient: apiClient, sharedFileService: sharedFile),
            tokenProvider: tokenProvider,
            sharedFileService: sharedFile,
            sessionSamplesKey: "sessionPacingSamples.\(suffix)"
        )
        // Re-publish its changes so the menu bar and any view observing this
        // store repaint when the work account updates.
        workCancellable = store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
        workUsageStore = store
        configureWorkStore?(store)
    }

    // MARK: - Display
}

/// The work account has no Claude Desktop login to fall back on: its token
/// comes from its own Keychain item or nowhere.
private struct NoClaudeDesktopConfig: ClaudeConfigReaderProtocol {
    func readEncryptedToken() -> String? { nil }
}

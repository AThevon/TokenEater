import Foundation
import Combine

/// What the surfaces need to know about the tracked Claude accounts.
@MainActor
protocol AccountsStoreProtocol: AnyObject {
    /// Every tracked account, main first.
    var records: [ClaudeAccountRecord] { get }
    /// The main account and every added account that is not paused, in
    /// display order.
    var activeAccountIDs: [AccountID] { get }
    /// Two or more accounts, paused ones included. Turns the identity check on.
    var tracksMultipleAccounts: Bool { get }
    /// Two or more running accounts. Below that every surface looks exactly
    /// as it did before accounts existed.
    var showsAccountMarkers: Bool { get }
    func record(for id: AccountID) -> ClaudeAccountRecord?
    /// The store holding an account's usage. `.main` is the app's main store.
    func usageStore(for id: AccountID) -> UsageStore?
}

/// What an added account runs on.
struct AccountRuntime {
    let store: UsageStore
    /// Its own `shared-acct-<uuid>.json`, next to `shared.json`.
    let sharedFile: SharedFileServiceProtocol
}

/// Owns the tracked Claude accounts and one `UsageStore` per added account.
///
/// The main account keeps the app's existing `UsageStore`; this store only
/// adds to it. Nothing here scans for accounts or reads a credential: an
/// account exists because the user added it, and its store reads its token
/// when it is started. With a single account nothing is written and no
/// profile is fetched on the refresh path, so an install that never adds one
/// behaves exactly as before.
///
/// The added stores are not relayed through this store's `objectWillChange`:
/// a surface that shows one observes it directly, and the menu bar merges
/// them in `StatusBarController.observeStoreChanges`.
@MainActor
final class AccountsStore: ObservableObject, AccountsStoreProtocol {
    @Published private(set) var records: [ClaudeAccountRecord]
    /// Added accounts only, paused ones included (they keep their last
    /// numbers on screen in Settings).
    @Published private(set) var runtimes: [AccountID: AccountRuntime]

    let mainStore: UsageStore
    /// Emits after an account is removed and its own files are gone, for the
    /// caller to purge the layouts that pointed at it.
    let accountRemoved = PassthroughSubject<AccountID, Never>()
    /// Emits after the main account moved to another config folder, for the
    /// file watcher, History and the session scan to follow it (#294).
    let mainScopeChanged = PassthroughSubject<CredentialScope, Never>()

    /// Applies the app's settings to an added account's store and starts it,
    /// or only loads its cache when it must not run. Set by
    /// `StatusBarController`; `index` is the account's position (the main
    /// account is 0) and `count` the number of accounts, for staggering.
    var configureStore: ((UsageStore, ClaudeAccountRecord, _ index: Int, _ count: Int) -> Void)?

    /// Finds candidate folders for the add-account sheet and the main
    /// account's folder picker. Never called on its own.
    let scanner: ClaudeConfigDirScannerProtocol

    typealias ConnectTokenProviderFactory = @Sendable (CredentialScope) -> TokenProviderProtocol

    private let defaults: UserDefaults
    private let home: String
    private let makeRuntime: @MainActor (ClaudeAccountRecord) -> AccountRuntime
    /// Builds the one-off provider `connect` reads a folder's login with.
    private let makeConnectTokenProvider: ConnectTokenProviderFactory
    /// Fetches the profile that identifies a login before it is added.
    private let apiClient: APIClientProtocol

    init(
        mainStore: UsageStore,
        defaults: UserDefaults = .standard,
        home: String = ClaudeConfigDirResolver.realHome(),
        scanner: ClaudeConfigDirScannerProtocol? = nil,
        makeConnectTokenProvider: ConnectTokenProviderFactory? = nil,
        apiClient: APIClientProtocol = APIClient(),
        makeRuntime: @escaping @MainActor (ClaudeAccountRecord) -> AccountRuntime = AccountsStore.liveRuntime
    ) {
        self.mainStore = mainStore
        self.defaults = defaults
        self.home = home
        self.scanner = scanner ?? ClaudeConfigDirScanner(home: home)
        self.makeConnectTokenProvider = makeConnectTokenProvider ?? { TokenProvider(scope: $0, home: home) }
        self.apiClient = apiClient
        self.makeRuntime = makeRuntime
        let loaded = Self.loadRecords(from: defaults)
        self.records = loaded
        var runtimes: [AccountID: AccountRuntime] = [:]
        for record in loaded where !record.id.isMain {
            runtimes[record.id] = makeRuntime(record)
        }
        self.runtimes = runtimes

        mainStore.onIdentityDigest = { [weak self] digest in
            self?.captureMainDigest(digest)
        }
        installIdentityGates()
    }

    // MARK: - Reading

    nonisolated static func loadRecords(from defaults: UserDefaults) -> [ClaudeAccountRecord] {
        ClaudeAccountsStorage.load(from: defaults)
    }

    var mainRecord: ClaudeAccountRecord { records[0] }

    var activeAccountIDs: [AccountID] {
        records.filter { !$0.isPaused }.map(\.id)
    }

    var tracksMultipleAccounts: Bool { records.count >= 2 }

    var showsAccountMarkers: Bool { activeAccountIDs.count >= 2 }

    func record(for id: AccountID) -> ClaudeAccountRecord? {
        records.first { $0.id == id }
    }

    func usageStore(for id: AccountID) -> UsageStore? {
        id.isMain ? mainStore : runtimes[id]?.store
    }

    /// Every Claude store, main first, then the added accounts in display
    /// order. What the settings sinks walk.
    var allStores: [UsageStore] {
        [mainStore] + records.dropFirst().compactMap { runtimes[$0.id]?.store }
    }

    // MARK: - Runtime

    /// The recipe for an added account: its own shared file (no migrations,
    /// no identity in it), its own folder-scoped token provider, its own
    /// pacing samples and notification state, and no reload of the widgets,
    /// none of which reads its file.
    static func liveRuntime(_ record: ClaudeAccountRecord) -> AccountRuntime {
        let file = SharedFileService(fileName: "shared-\(record.id.rawValue).json")
        let store = UsageStore(
            repository: UsageRepository(apiClient: APIClient(), sharedFileService: file),
            tokenProvider: TokenProvider(scope: record.scope),
            sharedFileService: file,
            notificationService: NotificationService(
                stateStore: UserDefaultsNotificationStateStore(keySuffix: record.id.storageSuffix)
            ),
            sessionSamplesKey: sessionSamplesKey(for: record.id),
            reloadWidgets: {}
        )
        return AccountRuntime(store: store, sharedFile: file)
    }

    static func sessionSamplesKey(for id: AccountID) -> String {
        "sessionPacingSamples" + id.storageSuffix
    }

    /// Hands every added account to `configureStore`, in display order.
    func configureAll() {
        let count = records.count
        for (index, record) in records.enumerated() where !record.id.isMain {
            guard let store = runtimes[record.id]?.store else { continue }
            configureStore?(store, record, index, count)
        }
    }

    /// The folders the tracked accounts read, normalized, the main account's
    /// default folder included. The scanner leaves them out.
    var trackedPaths: Set<String> {
        Set(records.map { record in
            ClaudeConfigDirResolver.normalize(
                record.configDir ?? ClaudeConfigDirResolver.defaultDirectory(home: home),
                home: home
            )
        })
    }

    // MARK: - Connecting

    /// Reads a folder's login once and identifies it, without adding
    /// anything. The only credential read of the whole add flow happens
    /// here: `/usr/bin/security` on the folder's exact service, then the
    /// folder's `.credentials.json`; Claude Desktop is never consulted. No
    /// usage is fetched before `commit`.
    ///
    /// `knownService` is the service the scanner found an item under, when it
    /// did; without it the folder is inspected first (attributes only).
    func connect(
        configDir: String,
        knownService: String? = nil,
        proxyConfig: ProxyConfig? = nil
    ) async -> AccountConnectResult {
        let folder = ClaudeConfigDirResolver.normalize(configDir, home: home)
        guard !isTracked(folder: folder) else { return .alreadyTracked }

        let login: IdentifiedLogin
        switch await identifyLogin(folder: folder, knownService: knownService, proxyConfig: proxyConfig) {
        case .refused(let refusal): return refusal
        case .identified(let identified): login = identified
        }

        // A second copy of the main account can only be refused if the main
        // account's identity is known; with one account it is kept in memory
        // as profiles come in, and fetched here when none came yet.
        var mainDigest = records[0].identityDigest
        if mainDigest == nil {
            mainDigest = await mainStore.ensureIdentityDigest()
        }
        guard !isTracked(folder: folder) else { return .alreadyTracked }
        if mainDigest == login.digest {
            return .duplicate(of: records[0].summary)
        }
        if let owner = records.first(where: { $0.identityDigest == login.digest }) {
            return .duplicate(of: owner.summary)
        }

        return .ready(PendingAccount(
            configDir: folder,
            service: login.service,
            digest: login.digest,
            plan: login.plan,
            organizationName: login.organizationName,
            maskedEmail: login.maskedEmail,
            proposedName: ClaudeConfigDirResolver.proposedName(forConfigDir: folder, existing: records.map(\.name)),
            proposedColorHex: AccountPalette.nextColor(excluding: records.map(\.colorHex))
        ))
    }

    /// Adds a connected folder under the name and colour the user chose, and
    /// starts it. From here on two or more accounts are tracked, so every
    /// store checks its login before writing. Nil when the folder or its
    /// login got tracked in the meantime.
    @discardableResult
    func commit(_ pending: PendingAccount, name: String, colorHex: String) -> ClaudeAccountRecord? {
        guard !records.contains(where: { $0.identityDigest == pending.digest }) else { return nil }
        let record = ClaudeAccountRecord(
            id: .makeExtra(),
            configDir: pending.configDir,
            service: pending.service,
            name: AccountNameRules.sanitize(name, fallback: pending.proposedName),
            colorHex: AccountPalette.normalizedHex(colorHex) ?? pending.proposedColorHex,
            isPaused: false,
            notificationsEnabled: true,
            identityDigest: pending.digest,
            addedAt: Date()
        )
        guard add(record) else { return nil }
        return self.record(for: record.id)
    }

    /// A login read and identified for a folder.
    struct IdentifiedLogin: Sendable {
        let service: String
        let digest: String
        let plan: PlanType
        let organizationName: String?
        let maskedEmail: String?
    }

    enum LoginIdentification: Sendable {
        case identified(IdentifiedLogin)
        case refused(AccountConnectResult)
    }

    /// The read-then-profile step shared by `connect` and the main account's
    /// folder change. One `currentToken()` off the main thread, one profile
    /// call; the token goes no further than this function.
    func identifyLogin(
        folder: String,
        knownService: String?,
        proxyConfig: ProxyConfig?
    ) async -> LoginIdentification {
        let command = ClaudeConfigDirResolver.loginCommand(forConfigDir: folder, home: home)
        let service: String
        if let knownService {
            service = knownService
        } else {
            let scanner = self.scanner
            let inspected = await Task.detached(priority: .userInitiated) { scanner.inspect(path: folder) }.value
            service = inspected.matchedService
                ?? ClaudeConfigDirResolver.serviceCandidates(for: folder, home: home).first
                ?? ClaudeConfigDirResolver.service(forHashInput: folder)
        }

        let provider = makeConnectTokenProvider(.configDir(path: folder, service: service))
        let read = await Task.detached(priority: .userInitiated) {
            (token: provider.currentToken(), diagnostic: provider.tokenDiagnostic)
        }.value
        guard let token = read.token else {
            switch read.diagnostic.keychainFailure {
            case .accessDenied: return .refused(.accessDenied)
            case .timedOut: return .refused(.timedOut)
            default: return .refused(.noLogin(command: command))
            }
        }

        let profile: ProfileResponse
        do {
            profile = try await apiClient.fetchProfile(token: token, proxyConfig: proxyConfig)
        } catch let error as APIError {
            switch error {
            case .tokenExpired, .noToken: return .refused(.expired(command: command))
            default: return .refused(.network(error.localizedDescription))
            }
        } catch {
            return .refused(.network(error.localizedDescription))
        }

        return .identified(IdentifiedLogin(
            service: service,
            digest: ClaudeConfigDirResolver.identityDigest(
                accountUUID: profile.account.uuid,
                organizationUUID: profile.organization?.uuid
            ),
            plan: PlanType(from: profile.account, organization: profile.organization),
            organizationName: profile.organization?.name,
            maskedEmail: ClaudeConfigDirResolver.maskEmail(profile.account.email)
        ))
    }

    // MARK: - Changes

    /// Starts tracking an added account. Refused for the main id, an id
    /// already tracked, or a folder some account already reads.
    @discardableResult
    func add(_ record: ClaudeAccountRecord) -> Bool {
        guard !record.id.isMain,
              records.allSatisfy({ $0.id != record.id }),
              let dir = record.configDir,
              !isTracked(folder: dir) else { return false }
        var record = record
        record.configDir = ClaudeConfigDirResolver.normalize(dir, home: home)
        record.name = AccountNameRules.sanitize(record.name)
        record.colorHex = AccountPalette.normalizedHex(record.colorHex)
            ?? AccountPalette.nextColor(excluding: records.map(\.colorHex))
        let runtime = makeRuntime(record)
        records.append(record)
        runtimes[record.id] = runtime
        persist()
        installIdentityGates()
        configureStore?(runtime.store, record, records.count - 1, records.count)
        return true
    }

    /// Whether a folder is already read by a tracked account, the main one's
    /// default folder included.
    func isTracked(folder: String) -> Bool {
        let wanted = ClaudeConfigDirResolver.normalize(folder, home: home)
        return records.contains { record in
            let dir = record.configDir ?? ClaudeConfigDirResolver.defaultDirectory(home: home)
            return ClaudeConfigDirResolver.normalize(dir, home: home) == wanted
        }
    }

    /// Edits what the user owns on a record: its name, colour and
    /// notification switch. The folder and the identity have their own
    /// paths (`setMainScope`, `acceptIdentity`) and are kept as they were.
    func update(_ id: AccountID, _ mutate: (inout ClaudeAccountRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let before = records[index]
        var next = before
        mutate(&next)
        next.configDir = before.configDir
        next.service = before.service
        next.identityDigest = before.identityDigest
        next.isPaused = before.isPaused
        next.name = AccountNameRules.sanitize(next.name, fallback: before.name)
        next.colorHex = AccountPalette.normalizedHex(next.colorHex) ?? before.colorHex
        guard next != before else { return }
        records[index] = next
        persist()
    }

    /// Pauses or resumes an added account. A paused account makes no call
    /// and reads no credential; its last numbers stay, dated. The main
    /// account stops only with Claude itself.
    func setPaused(_ paused: Bool, for id: AccountID) {
        guard !id.isMain,
              let index = records.firstIndex(where: { $0.id == id }),
              records[index].isPaused != paused else { return }
        records[index].isPaused = paused
        persist()
        guard let store = runtimes[id]?.store else { return }
        if paused { store.stopAutoRefresh() }
        configureStore?(store, records[index], index, records.count)
    }

    /// Stops tracking an added account for good: its record, its store, its
    /// pacing samples and its shared file go. Claude Code's own login is
    /// never touched.
    func remove(_ id: AccountID) {
        guard !id.isMain, let index = records.firstIndex(where: { $0.id == id }) else { return }
        let runtime = runtimes[id]
        runtime?.store.stopAutoRefresh()
        runtime?.store.identityGate = nil
        records.remove(at: index)
        runtimes.removeValue(forKey: id)
        // Everything kept under the account's suffix in the app's defaults,
        // where `UsageStore` and the notification state live: its pacing
        // samples, its alert state, its own layouts.
        let standard = UserDefaults.standard
        for key in standard.dictionaryRepresentation().keys where key.hasSuffix(id.storageSuffix) {
            standard.removeObject(forKey: key)
        }
        if let url = runtime?.sharedFile.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        persist()
        installIdentityGates()
        accountRemoved.send(id)
    }

    /// Points the main account at another config folder, or back at
    /// `~/.claude` with nil (#294). The previous login's numbers are dropped
    /// and its identity forgotten; the next refresh reads the new folder.
    /// Refused when an added account already reads that folder.
    @discardableResult
    func setMainScope(configDir: String?, service: String?) -> Bool {
        var dir = configDir.map { ClaudeConfigDirResolver.normalize($0, home: home) }
        if let current = dir, ClaudeConfigDirResolver.isDefault(current, home: home) { dir = nil }
        if let dir {
            let taken = records.dropFirst().contains {
                $0.configDir.map { ClaudeConfigDirResolver.normalize($0, home: home) } == dir
            }
            guard !taken else { return false }
        }
        let resolvedService = dir.map { folder in
            (service?.isEmpty == false ? service : nil)
                ?? ClaudeConfigDirResolver.serviceCandidates(for: folder, home: home).first
                ?? ClaudeConfigDirResolver.service(forHashInput: folder)
        }
        var main = records[0]
        main.configDir = dir
        main.service = resolvedService
        main.identityDigest = nil
        records[0] = main
        persist()
        let scope = main.scope
        mainStore.reconfigure(scope: scope)
        mainScopeChanged.send(scope)
        return true
    }

    // MARK: - Identity

    /// The verdict on a login digest for an account:
    /// - another tracked account's digest: it belongs to that account;
    /// - this account has none yet: accepted, and kept;
    /// - its own digest: accepted;
    /// - anything else: the folder now signs in to someone new.
    func identityVerdict(for digest: String, account id: AccountID) -> IdentityVerdict {
        if let other = records.first(where: { $0.id != id && $0.identityDigest == digest }) {
            return .belongsTo(other.id)
        }
        guard let index = records.firstIndex(where: { $0.id == id }) else { return .accepted }
        guard let known = records[index].identityDigest else {
            records[index].identityDigest = digest
            persist()
            return .accepted
        }
        return known == digest ? .accepted : .changed(newDigest: digest)
    }

    /// Takes the login a folder now holds as the account's own, after the
    /// user said so. Refused when that login is another tracked account's.
    @discardableResult
    func acceptIdentity(_ digest: String, for id: AccountID) -> Bool {
        guard !records.contains(where: { $0.id != id && $0.identityDigest == digest }),
              let index = records.firstIndex(where: { $0.id == id }) else { return false }
        records[index].identityDigest = digest
        persist()
        return true
    }

    /// Keeps the main account's digest current while it is the only account,
    /// in memory only: it follows whatever login is active, and an install
    /// with one account never writes the account list. The value is there
    /// when a second account is connected, to refuse a duplicate.
    private func captureMainDigest(_ digest: String) {
        guard !tracksMultipleAccounts, records[0].identityDigest != digest else { return }
        records[0].identityDigest = digest
    }

    /// One account follows the active login with no check; from two, every
    /// store checks its login before writing anything.
    private func installIdentityGates() {
        guard tracksMultipleAccounts else {
            if mainStore.identityGate != nil { mainStore.identityGate = nil }
            return
        }
        for store in [(AccountID.main, mainStore)] + runtimes.map({ ($0.key, $0.value.store) }) {
            let id = store.0
            store.1.identityGate = { [weak self] digest in
                self?.identityVerdict(for: digest, account: id) ?? .accepted
            }
        }
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(ClaudeAccountsStorage.encode(records), forKey: ClaudeAccountsStorage.defaultsKey)
    }
}

import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var fiveHourPct: Int = 0
    @Published var sevenDayPct: Int = 0
    @Published var sonnetPct: Int = 0
    @Published var fiveHourReset: String = ""
    @Published var pacingDelta: Int = 0
    @Published var pacingZone: PacingZone = .onTrack
    @Published var pacingResult: PacingResult?
    @Published var lastUpdate: Date?
    @Published var isLoading = false
    @Published var errorState: AppErrorState = .none
    @Published var hasConfig = false
    @Published var opusPct: Int = 0
    @Published var coworkPct: Int = 0
    @Published var oauthAppsPct: Int = 0
    @Published var hasOpus: Bool = false
    @Published var hasCowork: Bool = false
    @Published var planType: PlanType = .unknown
    @Published var rateLimitTier: String?
    @Published var organizationName: String?
    @Published private(set) var lastUsage: UsageResponse?

    var hasError: Bool { errorState != .none }

    var isDisconnected: Bool {
        errorState == .tokenUnavailable
    }

    var pacingMargin: Int = 10

    /// Token that last received a 401/403. Prevents retrying the API with a known-dead token.
    private var lastFailedToken: String?

    private let repository: UsageRepositoryProtocol
    private let keychainService: KeychainServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    /// Backoff for 429 responses: uses Retry-After header when available, otherwise exponential.
    private var consecutive429Count: Int = 0
    private var last429Date: Date?
    private var retryAfterInterval: TimeInterval?
    private static let normalInterval: TimeInterval = 300
    private static let backoffMax: TimeInterval = 600

    var proxyConfig: ProxyConfig?

    // MARK: - Temporary token management (will be replaced by TokenProvider in Task 7)

    private var _currentToken: String?

    var isConfigured: Bool { _currentToken != nil }
    var currentToken: String? { _currentToken }

    func syncCredentialsFile() {
        if let token = keychainService.readToken(), token != _currentToken {
            _currentToken = token
        }
    }

    func syncKeychainSilently() {
        if let token = keychainService.readKeychainTokenSilently(), token != _currentToken {
            _currentToken = token
        }
    }

    var cachedUsage: CachedUsage? {
        SharedFileService().cachedUsage
    }

    init(
        repository: UsageRepositoryProtocol = UsageRepository(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        notificationService: NotificationServiceProtocol = NotificationService()
    ) {
        self.repository = repository
        self.keychainService = keychainService
        self.notificationService = notificationService
    }

    func refresh(thresholds: UsageThresholds = .default, force: Bool = false) async {
        // Prevent concurrent refreshes — multiple .task/.onAppear can race
        guard !isLoading else { return }

        // Throttle: skip if a successful refresh happened less than 55s ago (avoids 429)
        if !force, let last = lastUpdate, Date().timeIntervalSince(last) < 55 {
            return
        }

        // Back off: skip non-forced refreshes while in 429 backoff window
        if !force, consecutive429Count > 0, let last = last429Date,
           Date().timeIntervalSince(last) < currentBackoff {
            return
        }

        // Token recovery — credentials file first, then silent Keychain fallback.
        if !isConfigured || lastFailedToken == _currentToken {
            syncCredentialsFile()
            if !isConfigured || lastFailedToken == _currentToken {
                syncKeychainSilently()
            }
            if let currentToken = _currentToken, currentToken != lastFailedToken {
                lastFailedToken = nil
                errorState = .none
            }
        }

        guard isConfigured,
              let token = _currentToken,
              token != lastFailedToken else {
            hasConfig = lastFailedToken != nil
            return
        }
        hasConfig = true
        isLoading = true
        defer { isLoading = false }
        do {
            let usage = try await repository.refreshUsage(token: token, proxyConfig: proxyConfig)
            update(from: usage)
            errorState = .none
            lastFailedToken = nil
            consecutive429Count = 0
            last429Date = nil
            retryAfterInterval = nil
            lastUpdate = Date()
            WidgetReloader.scheduleReload()
            notificationService.checkThresholds(
                fiveHour: MetricSnapshot(pct: fiveHourPct, resetsAt: usage.fiveHour?.resetsAtDate),
                sevenDay: MetricSnapshot(pct: sevenDayPct, resetsAt: usage.sevenDay?.resetsAtDate),
                sonnet: MetricSnapshot(pct: sonnetPct, resetsAt: usage.sevenDaySonnet?.resetsAtDate),
                pacingZone: pacingZone,
                thresholds: thresholds
            )
        } catch let error as APIError {
            switch error {
            case .tokenExpired, .noToken:
                lastFailedToken = _currentToken
                errorState = .tokenUnavailable
            case .rateLimited(let retryAfter):
                consecutive429Count += 1
                last429Date = Date()
                retryAfterInterval = retryAfter
                errorState = .rateLimited
            default:
                errorState = .networkError
            }
        } catch {
            errorState = .networkError
        }
    }

    func loadCached() {
        if let cached = cachedUsage {
            update(from: cached.usage)
            lastUpdate = cached.fetchDate
        }
    }

    func reloadConfig(thresholds: UsageThresholds = .default) {
        syncCredentialsFile()
        if !isConfigured {
            syncKeychainSilently()
        }
        lastFailedToken = nil
        errorState = .none
        hasConfig = isConfigured
        loadCached()
        notificationService.requestPermission()
        WidgetReloader.scheduleReload()
        refreshTask?.cancel()
        refreshTask = Task {
            await refresh(thresholds: thresholds)
        }
    }

    func startAutoRefresh(interval: TimeInterval = 300, thresholds: UsageThresholds = .default) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            // Wait first — reloadConfig already triggers an initial refresh
            try? await Task.sleep(for: .seconds(interval))
            // Fetch profile once on first cycle (deferred from startup to save rate limit)
            if let self { await self.refreshProfile() }
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(thresholds: thresholds)
                let delay = self.currentBackoff
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Current backoff duration based on 429 state. Always >= normalInterval to never retry faster than normal.
    private var currentBackoff: TimeInterval {
        guard consecutive429Count > 0 else { return Self.normalInterval }
        if let retryAfter = retryAfterInterval, retryAfter > 0 {
            return max(retryAfter, Self.normalInterval)
        }
        let exponential = Self.normalInterval * pow(2.0, Double(consecutive429Count - 1))
        return min(exponential, Self.backoffMax)
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
    }

    func reauthenticate() async {
        syncCredentialsFile()
        if !isConfigured {
            syncKeychainSilently()
        }
        if isConfigured, _currentToken != lastFailedToken {
            lastFailedToken = nil
            errorState = .none
            hasConfig = true
            await refresh(force: true)
        }
    }

    func testConnection() async -> ConnectionTestResult {
        guard let token = _currentToken else {
            return ConnectionTestResult(success: false, message: String(localized: "error.notoken"))
        }
        return await apiClient_testConnection(token: token, proxyConfig: proxyConfig)
    }

    /// Temporary wrapper — will be removed in Task 7 when UsageStore is rewritten
    private func apiClient_testConnection(token: String, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        do {
            _ = try await repository.testConnection(token: token, proxyConfig: proxyConfig)
            return ConnectionTestResult(success: true, message: "OK")
        } catch {
            return ConnectionTestResult(success: false, message: error.localizedDescription)
        }
    }

    func connectAutoDetect() async -> ConnectionTestResult {
        syncCredentialsFile()
        if !isConfigured {
            syncKeychainSilently()
        }
        guard let token = _currentToken else {
            return ConnectionTestResult(success: false, message: String(localized: "error.notoken"))
        }
        let result = await apiClient_testConnection(token: token, proxyConfig: proxyConfig)
        if result.success {
            hasConfig = true
        }
        return result
    }

    private var lastProfileFetch: Date?

    func refreshProfile() async {
        guard let token = _currentToken else { return }
        // Throttle: profile rarely changes, skip if fetched less than 5min ago
        if let last = lastProfileFetch, Date().timeIntervalSince(last) < 300 { return }
        do {
            let profile = try await repository.fetchProfile(token: token, proxyConfig: proxyConfig)
            planType = PlanType(from: profile.account, organization: profile.organization)
            rateLimitTier = profile.organization?.rateLimitTier
            organizationName = profile.organization?.name
            lastProfileFetch = Date()
        } catch {
            // Profile fetch failure is non-critical — don't update errorState
        }
    }

    // MARK: - Private

    private func update(from usage: UsageResponse) {
        lastUsage = usage
        fiveHourPct = Int(usage.fiveHour?.utilization ?? 0)
        sevenDayPct = Int(usage.sevenDay?.utilization ?? 0)
        sonnetPct = Int(usage.sevenDaySonnet?.utilization ?? 0)
        opusPct = Int(usage.sevenDayOpus?.utilization ?? 0)
        coworkPct = Int(usage.sevenDayCowork?.utilization ?? 0)
        oauthAppsPct = Int(usage.sevenDayOauthApps?.utilization ?? 0)
        hasOpus = usage.sevenDayOpus != nil
        hasCowork = usage.sevenDayCowork != nil

        if let reset = usage.fiveHour?.resetsAtDate {
            let diff = reset.timeIntervalSinceNow
            if diff > 0 {
                let h = Int(diff) / 3600
                let m = (Int(diff) % 3600) / 60
                fiveHourReset = h > 0 ? "\(h)h \(m)min" : "\(m)min"
            } else {
                fiveHourReset = String(localized: "relative.now")
            }
        } else {
            fiveHourReset = ""
        }

        if let pacing = PacingCalculator.calculate(from: usage, margin: Double(pacingMargin)) {
            pacingDelta = Int(pacing.delta)
            pacingZone = pacing.zone
            pacingResult = pacing
        }
    }

    func recalculatePacing() {
        guard let usage = lastUsage else { return }
        if let pacing = PacingCalculator.calculate(from: usage, margin: Double(pacingMargin)) {
            pacingDelta = Int(pacing.delta)
            pacingZone = pacing.zone
            pacingResult = pacing
        }
    }
}

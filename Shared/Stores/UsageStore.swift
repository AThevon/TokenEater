import SwiftUI

enum RefreshSpeed: TimeInterval {
    case fast = 120      // After FSEvents token change — 2min
    case normal = 300    // Steady state — configurable via settings (default 5min)
    case slow = 1200     // After 429 — 2x normal or 20min minimum
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var fiveHourPct: Int = 0
    @Published var sevenDayPct: Int = 0
    @Published var sonnetPct: Int = 0
    @Published var fiveHourReset: String = ""
    @Published var fiveHourResetAbsolute: String = ""
    @Published var sevenDayReset: String = ""
    @Published var sevenDayResetAbsolute: String = ""
    @Published var pacingDelta: Int = 0
    @Published var pacingZone: PacingZone = .onTrack
    @Published var pacingResult: PacingResult?
    @Published var fiveHourPacing: PacingResult?
    @Published var sonnetPacing: PacingResult?
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
    /// Base refresh interval in seconds (from settings, default 300)
    var refreshIntervalSeconds: TimeInterval = 300

    private let repository: UsageRepositoryProtocol
    private let tokenProvider: TokenProviderProtocol
    private let sharedFileService: SharedFileServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    /// Current adaptive speed for rate limiting
    private(set) var currentSpeed: RefreshSpeed = .normal

    /// When fast mode was activated (resets to normal after 10 minutes)
    private var fastModeStart: Date?

    /// Retry-After date from last 429 response
    private(set) var retryAfterDate: Date?

    /// Effective interval based on current speed + user setting
    var effectiveInterval: TimeInterval {
        switch currentSpeed {
        case .fast: return min(120, refreshIntervalSeconds)
        case .normal: return refreshIntervalSeconds
        case .slow: return max(refreshIntervalSeconds * 2, 1200)
        }
    }

    var proxyConfig: ProxyConfig?

    var cachedUsage: CachedUsage? {
        sharedFileService.cachedUsage
    }

    init(
        repository: UsageRepositoryProtocol = UsageRepository(),
        tokenProvider: TokenProviderProtocol = TokenProvider(),
        sharedFileService: SharedFileServiceProtocol = SharedFileService(),
        notificationService: NotificationServiceProtocol = NotificationService()
    ) {
        self.repository = repository
        self.tokenProvider = tokenProvider
        self.sharedFileService = sharedFileService
        self.notificationService = notificationService
    }

    func refresh(thresholds: UsageThresholds = .default, force: Bool = false) async {
        // Prevent concurrent refreshes
        guard !isLoading else { return }

        // Resolve token
        guard let token = tokenProvider.currentToken() else {
            hasConfig = false
            errorState = .tokenUnavailable
            return
        }
        hasConfig = true

        // Decay fast mode after 10 minutes
        if currentSpeed == .fast, let start = fastModeStart,
           Date().timeIntervalSince(start) > 600 {
            currentSpeed = .normal
            fastModeStart = nil
        }

        // Interval check using currentSpeed
        if !force, let last = lastUpdate,
           Date().timeIntervalSince(last) < effectiveInterval {
            return
        }

        // Respect Retry-After from previous 429 response
        if !force, let retryAfter = retryAfterDate, Date() < retryAfter {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let usage = try await repository.refreshUsage(token: token, proxyConfig: proxyConfig)
            updateUI(from: usage)
            errorState = .none
            lastUpdate = Date()
            // Reset slow speed on success
            if currentSpeed == .slow {
                currentSpeed = .normal
            }
            retryAfterDate = nil
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
                // Invalidate cached token so next read re-checks Keychain for a fresh one
                tokenProvider.invalidateToken()
                // Retry once with a fresh token
                if let freshToken = tokenProvider.currentToken(), freshToken != token {
                    do {
                        let usage = try await repository.refreshUsage(token: freshToken, proxyConfig: proxyConfig)
                        updateUI(from: usage)
                        errorState = .none
                        lastUpdate = Date()
                        if currentSpeed == .slow {
                            currentSpeed = .normal
                        }
                        retryAfterDate = nil
                        WidgetReloader.scheduleReload()
                        notificationService.checkThresholds(
                            fiveHour: MetricSnapshot(pct: fiveHourPct, resetsAt: usage.fiveHour?.resetsAtDate),
                            sevenDay: MetricSnapshot(pct: sevenDayPct, resetsAt: usage.sevenDay?.resetsAtDate),
                            sonnet: MetricSnapshot(pct: sonnetPct, resetsAt: usage.sevenDaySonnet?.resetsAtDate),
                            pacingZone: pacingZone,
                            thresholds: thresholds
                        )
                        return
                    } catch {
                        // Retry also failed — fall through to set error
                    }
                }
                errorState = .tokenUnavailable
            case .rateLimited(let retryAfter):
                currentSpeed = .slow
                // /api/oauth/usage returns retry-after: 0 when the token has hit its per-token
                // request limit (not a transient throttle). A value of 0 or a missing header
                // both signal the same "token exhausted" state — default to 6 hours so we stop
                // hammering the endpoint every 20 minutes.
                let backoff: TimeInterval = retryAfter.flatMap { $0 > 0 ? $0 : nil } ?? (6 * 3600)
                retryAfterDate = Date().addingTimeInterval(backoff)
                errorState = .rateLimited
            default:
                errorState = .networkError
            }
        } catch {
            errorState = .networkError
        }
    }

    /// Only refreshes if lastUpdate is older than 120 seconds (for wake handler)
    func refreshIfStale(thresholds: UsageThresholds = .default) async {
        guard lastUpdate == nil || Date().timeIntervalSince(lastUpdate!) > 120 else { return }
        await refresh(thresholds: thresholds, force: true)
    }

    /// Switch to fast mode for FSEvents token changes
    func switchToFastMode() {
        currentSpeed = .fast
        fastModeStart = Date()
    }

    /// Called when the token file changes on disk or the user taps "Retry now".
    /// Invalidates the cached token so the next refresh reads a fresh one,
    /// and clears the rate-limit backoff so the refresh actually fires.
    func handleTokenChange() {
        tokenProvider.invalidateToken()
        retryAfterDate = nil
        switchToFastMode()
    }

    func loadCached() {
        if let cached = cachedUsage {
            updateUI(from: cached.usage)
            lastUpdate = cached.fetchDate
        }
    }

    func reloadConfig(thresholds: UsageThresholds = .default) {
        let token = tokenProvider.currentToken()
        hasConfig = token != nil
        errorState = token != nil ? .none : .tokenUnavailable
        loadCached()
        notificationService.requestPermission()
        WidgetReloader.scheduleReload()
        refreshTask?.cancel()
        refreshTask = Task {
            await refresh(thresholds: thresholds, force: true)
            // Fetch the profile right after the first usage refresh so the
            // plan badge (PRO / MAX / TEAM) shows up immediately instead of
            // waiting 10 minutes for the auto-refresh cycle. `refreshProfile`
            // is internally throttled to 5 min, so this is safe to call on
            // every reload.
            await refreshProfile()
        }
    }

    func startAutoRefresh(interval: TimeInterval = 600, thresholds: UsageThresholds = .default) {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            // Wait first — reloadConfig already triggers an initial refresh
            try? await Task.sleep(for: .seconds(interval))
            // Fetch profile once on first cycle (deferred from startup to save rate limit)
            if let self { await self.refreshProfile() }
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(thresholds: thresholds)
                let delay = self.effectiveInterval
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
    }

    func reauthenticate() async {
        await refresh(force: true)
    }

    func testConnection() async -> ConnectionTestResult {
        guard let token = tokenProvider.currentToken() else {
            return ConnectionTestResult(success: false, message: String(localized: "error.notoken"))
        }
        do {
            _ = try await repository.testConnection(token: token, proxyConfig: proxyConfig)
            return ConnectionTestResult(success: true, message: "OK")
        } catch {
            return ConnectionTestResult(success: false, message: error.localizedDescription)
        }
    }

    func connectAutoDetect() async -> ConnectionTestResult {
        guard let token = tokenProvider.currentToken() else {
            return ConnectionTestResult(success: false, message: String(localized: "error.notoken"))
        }
        do {
            _ = try await repository.testConnection(token: token, proxyConfig: proxyConfig)
            hasConfig = true
            return ConnectionTestResult(success: true, message: "OK")
        } catch {
            return ConnectionTestResult(success: false, message: error.localizedDescription)
        }
    }

    private var lastProfileFetch: Date?

    func refreshProfile() async {
        guard let token = tokenProvider.currentToken() else { return }
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

    func updateUI(from usage: UsageResponse) {
        lastUsage = usage
        fiveHourPct = Int(usage.fiveHour?.utilization ?? 0)
        sevenDayPct = Int(usage.sevenDay?.utilization ?? 0)
        sonnetPct = Int(usage.sevenDaySonnet?.utilization ?? 0)
        opusPct = Int(usage.sevenDayOpus?.utilization ?? 0)
        coworkPct = Int(usage.sevenDayCowork?.utilization ?? 0)
        oauthAppsPct = Int(usage.sevenDayOauthApps?.utilization ?? 0)
        hasOpus = usage.sevenDayOpus != nil
        hasCowork = usage.sevenDayCowork != nil

        refreshResetCountdown()

        applyPacing(PacingCalculator.calculateAll(from: usage, margin: Double(pacingMargin)))
    }

    func refreshResetCountdown() {
        let session = ResetCountdownFormatter.session(from: lastUsage?.fiveHour?.resetsAtDate)
        fiveHourReset = session.relative
        fiveHourResetAbsolute = session.absolute
        let weekly = ResetCountdownFormatter.weekly(from: lastUsage?.sevenDay?.resetsAtDate)
        sevenDayReset = weekly.relative
        sevenDayResetAbsolute = weekly.absolute
    }

    func recalculatePacing() {
        guard let usage = lastUsage else { return }
        applyPacing(PacingCalculator.calculateAll(from: usage, margin: Double(pacingMargin)))
    }

    private func applyPacing(_ allPacing: [PacingBucket: PacingResult]) {
        if let pacing = allPacing[.sevenDay] {
            pacingDelta = Int(pacing.delta)
            pacingZone = pacing.zone
            pacingResult = pacing
        } else {
            pacingDelta = 0
            pacingZone = .onTrack
            pacingResult = nil
        }
        fiveHourPacing = allPacing[.fiveHour]
        sonnetPacing = allPacing[.sonnet]
    }
}

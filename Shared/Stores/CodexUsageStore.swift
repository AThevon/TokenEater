import SwiftUI

/// Codex counterpart of `UsageStore`: owns the Codex usage state, drives its own
/// refresh loop and fires Codex notifications.
///
/// Kept as a separate store rather than a generalisation of `UsageStore` because
/// the two payloads have genuinely different shapes (Anthropic returns a fixed
/// set of named buckets, Codex one or two windows whose meaning depends on the
/// plan). The refresh, backoff and 401 semantics are deliberately mirrored
/// step for step so the two can never drift in behaviour.
@MainActor
final class CodexUsageStore: ObservableObject {

    // MARK: - Published Properties

    /// Whether the user tracks Codex at all. Wired from `SettingsStore` by
    /// `StatusBarController`; nothing polls or notifies while this is false.
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var authState: CodexAuthState = .notInstalled
    @Published var hasConfig = false
    @Published var isLoading = false
    @Published var errorState: AppErrorState = .none
    @Published var lastUpdate: Date?

    /// Session window first, then weekly, then anything unfamiliar.
    @Published private(set) var windows: [CodexWindowSnapshot] = []
    @Published private(set) var credits: CodexCredits?
    @Published private(set) var planType: CodexPlanType = .unknown
    @Published private(set) var limitReached: Bool = false
    @Published private(set) var additionalLimits: [CodexAdditionalRateLimit] = []
    @Published private(set) var lastUsage: CodexUsageResponse?
    /// Snapshot of the most recent API failure, for the diagnostic report.
    @Published private(set) var lastAPIError: LastAPIError?

    // MARK: - Public Properties

    var session: CodexWindowSnapshot? { windows.first { $0.kind == .session } }
    var weekly: CodexWindowSnapshot? { windows.first { $0.kind == .weekly } }

    var hasError: Bool { errorState != .none }

    var isDisconnected: Bool { errorState == .tokenUnavailable }

    /// The token is momentarily unusable but a previous snapshot is still worth
    /// showing. Mirrors `UsageStore.isAwaitingRefresh`: the calm "Codex will
    /// refresh this itself" case rather than the alarming re-auth banner.
    var isAwaitingRefresh: Bool { errorState == .tokenUnavailable && lastUsage != nil }

    /// Settings-fed knobs, wired by `StatusBarController` exactly like the
    /// Claude store's.
    var pacingMargin: Int = 10 {
        didSet {
            if isEnabled { sharedFileService.updatePacingMargin(Double(pacingMargin)) }
        }
    }
    var pacingSchedule: PacingSchedule = .rolling
    var refreshIntervalSeconds: TimeInterval = 300
    var proxyConfig: ProxyConfig?
    var notifTogglesProvider: (() -> NotificationToggles?)?

    var connectionStatus: String {
        if authState.isExpired() || (isEnabled && errorState == .tokenUnavailable && authState.isTrackable) {
            return String(localized: "codex.status.expired")
        }
        switch authState {
        case .notInstalled: return String(localized: "codex.status.notInstalled")
        case .noCredentials: return String(localized: "codex.status.noCredentials")
        case .apiKeyOnly: return String(localized: "codex.status.apiKey")
        case .chatgpt(_, _, let expiresAt):
            var status = String(localized: "codex.status.connected")
            let plan = planType == .unknown ? authState.planType : planType
            if plan != .unknown { status += " · " + plan.displayLabel }
            if let expiresAt {
                status += " · " + String(format: String(localized: "codex.status.validUntil"), expiresAt.formatted(date: .abbreviated, time: .omitted))
            }
            return status
        }
    }

    var cachedUsage: CachedCodexUsage? { sharedFileService.cachedUsage }

    // MARK: - Private Properties

    private let repository: CodexUsageRepositoryProtocol
    private let tokenProvider: CodexTokenProviderProtocol
    private let sharedFileService: CodexSharedFileServiceProtocol
    private let notificationService: NotificationServiceProtocol

    private var refreshGeneration = 0
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

    private(set) var currentSpeed: RefreshSpeed = .normal
    private var fastModeStart: Date?
    private(set) var retryAfterDate: Date?
    private var consecutiveRateLimits: Int = 0

    var effectiveInterval: TimeInterval {
        RateLimitBackoff.effectiveInterval(speed: currentSpeed, baseInterval: refreshIntervalSeconds)
    }

    // MARK: - Initializers

    init(
        repository: CodexUsageRepositoryProtocol = CodexUsageRepository(),
        tokenProvider: CodexTokenProviderProtocol = CodexTokenProvider(),
        sharedFileService: CodexSharedFileServiceProtocol = CodexSharedFileService(),
        notificationService: NotificationServiceProtocol = NotificationService()
    ) {
        self.repository = repository
        self.tokenProvider = tokenProvider
        self.sharedFileService = sharedFileService
        self.notificationService = notificationService
        self.authState = tokenProvider.authState
    }

    // MARK: - Public Methods

    /// Turns the provider on or off at runtime. Turning it off stops polling,
    /// clears the published state and drops both the widget payload and any
    /// scheduled Codex reminder, so nothing Codex-shaped survives the toggle.
    func setEnabled(_ enabled: Bool, thresholds: UsageThresholds = .default) {
        guard enabled != isEnabled else { return }
        refreshGeneration += 1
        isEnabled = enabled
        sharedFileService.updateEnabled(enabled)

        if enabled {
            sharedFileService.updatePacingMargin(Double(pacingMargin))
            reloadConfig(thresholds: thresholds)
            startAutoRefresh(thresholds: thresholds)
        } else {
            stopAutoRefresh()
            refreshTask?.cancel()
            resetState()
            notificationService.cancelCodexReminders()
        }
        WidgetReloader.scheduleReload()
    }

    func reloadConfig(thresholds: UsageThresholds = .default) {
        guard isEnabled else { return }
        authState = tokenProvider.authState
        let credentials = tokenProvider.currentCredentials()
        hasConfig = credentials != nil
        errorState = credentials != nil ? .none : .tokenUnavailable
        loadCached()
        WidgetReloader.scheduleReload()
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refresh(thresholds: thresholds, force: true)
        }
    }

    func refresh(thresholds: UsageThresholds = .default, force: Bool = false) async {
        guard isEnabled else { return }
        guard !isLoading else { return }

        authState = tokenProvider.authState
        guard let credentials = tokenProvider.currentCredentials() else {
            hasConfig = false
            errorState = .tokenUnavailable
            return
        }
        hasConfig = true

        // The access token lives ~10 days and only Codex can refresh it. When it
        // has already expired there is nothing to gain from a request that is
        // guaranteed to 401, so surface the state directly.
        if credentials.isExpired() {
            tokenProvider.invalidate()
            guard let fresh = tokenProvider.currentCredentials(), !fresh.isExpired() else {
                errorState = .tokenUnavailable
                notifyTokenExpired()
                return
            }
            await performRefresh(credentials: fresh, thresholds: thresholds)
            return
        }

        if currentSpeed == .fast, let start = fastModeStart, Date().timeIntervalSince(start) > 600 {
            currentSpeed = .normal
            fastModeStart = nil
        }

        if !force, let last = lastUpdate, Date().timeIntervalSince(last) < effectiveInterval {
            return
        }

        if !force, let retryAfter = retryAfterDate, Date() < retryAfter {
            return
        }

        await performRefresh(credentials: credentials, thresholds: thresholds)
    }

    /// Wake-from-sleep hook, matching `UsageStore.refreshIfStale`.
    func refreshIfStale(thresholds: UsageThresholds = .default) async {
        guard lastUpdate == nil || Date().timeIntervalSince(lastUpdate!) > 120 else { return }
        await refresh(thresholds: thresholds, force: true)
    }

    func startAutoRefresh(thresholds: UsageThresholds = .default) {
        guard isEnabled else { return }
        autoRefreshTask?.cancel()
        let initialDelay = effectiveInterval
        autoRefreshTask = Task { [weak self] in
            // reloadConfig already fired the first refresh.
            try? await Task.sleep(for: .seconds(initialDelay))
            while !Task.isCancelled {
                guard let self else { return }
                // Catches a token Codex refreshed and an account swap, neither of
                // which the file watcher can distinguish on its own.
                let rotated = self.reconcileCredentialsIfChanged()
                await self.refresh(thresholds: thresholds, force: rotated)
                try? await Task.sleep(for: .seconds(self.effectiveInterval))
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    /// Called when `auth.json` changes on disk or the user hits Retry.
    func handleAuthChange() {
        refreshGeneration += 1
        tokenProvider.invalidate()
        retryAfterDate = nil
        consecutiveRateLimits = 0
        authState = tokenProvider.authState
        switchToFastMode()
    }

    func switchToFastMode() {
        currentSpeed = .fast
        fastModeStart = Date()
    }

    /// True when the caller should force a refresh because the credentials
    /// changed under us.
    func reconcileCredentialsIfChanged() -> Bool {
        guard tokenProvider.refreshIfChanged() else { return false }
        retryAfterDate = nil
        consecutiveRateLimits = 0
        authState = tokenProvider.authState
        switchToFastMode()
        return true
    }

    func loadCached() {
        sharedFileService.invalidateCache()
        guard let cached = sharedFileService.cachedUsage else { return }
        updateUI(from: cached.usage)
        lastUpdate = cached.fetchDate
    }

    func testConnection() async -> ConnectionTestResult {
        guard let credentials = tokenProvider.currentCredentials() else {
            return ConnectionTestResult(success: false, message: String(localized: "codex.error.notLoggedIn"))
        }
        return await repository.testConnection(credentials: credentials, proxyConfig: proxyConfig)
    }

    /// Re-renders the countdown strings without refetching. Driven by the same
    /// one-minute timer the menu bar uses for the Claude reset segment.
    func refreshResetCountdown() {
        guard let usage = lastUsage else { return }
        applyWindows(from: usage)
    }

    func refreshNotificationSettings() {
        guard isEnabled else { return }
        evaluateNotifications()
    }

    func recalculatePacing() {
        guard let usage = lastUsage else { return }
        applyWindows(from: usage)
    }

    // MARK: - Private Methods

    private func performRefresh(credentials: CodexCredentials, thresholds: UsageThresholds) async {
        let generation = refreshGeneration
        isLoading = true
        defer {
            isLoading = false
            if generation != refreshGeneration {
                sharedFileService.clear()
                if isEnabled {
                    refreshTask = Task { [weak self] in
                        await self?.refresh(thresholds: thresholds, force: true)
                    }
                }
            }
        }

        do {
            let usage = try await repository.refreshUsage(credentials: credentials, proxyConfig: proxyConfig)
            guard generation == refreshGeneration, isEnabled, !Task.isCancelled else { return }
            applySuccess(usage: usage)
        } catch let error as APIError {
            guard generation == refreshGeneration, isEnabled, !Task.isCancelled else { return }
            lastAPIError = error.diagnosticSnapshot
            switch error {
            case .tokenExpired, .noToken:
                // Codex may have rotated the token between our cached read and
                // this request; retry once with whatever is on disk now.
                tokenProvider.invalidate()
                if let fresh = tokenProvider.currentCredentials(), fresh.accessToken != credentials.accessToken {
                    do {
                        let usage = try await repository.refreshUsage(credentials: fresh, proxyConfig: proxyConfig)
                        guard generation == refreshGeneration, isEnabled, !Task.isCancelled else { return }
                        applySuccess(usage: usage)
                        return
                    } catch {
                        // Fall through to the error state below.
                    }
                }
                guard generation == refreshGeneration, isEnabled, !Task.isCancelled else { return }
                authState = tokenProvider.authState
                errorState = .tokenUnavailable
                notifyTokenExpired()
            case .rateLimited(let retryAfter, _, _):
                currentSpeed = .slow
                let result = RateLimitBackoff.nextRetryDate(
                    consecutiveRateLimits: consecutiveRateLimits,
                    serverRetryAfter: retryAfter
                )
                consecutiveRateLimits = result.consecutiveRateLimits
                retryAfterDate = result.date
                errorState = .rateLimited
            default:
                errorState = .networkError
            }
        } catch {
            guard generation == refreshGeneration, isEnabled, !Task.isCancelled else { return }
            lastAPIError = LastAPIError(
                httpStatusCode: nil,
                retryAfterHeader: nil,
                endpoint: "/backend-api/wham/usage",
                timestamp: Date(),
                underlyingError: error.localizedDescription
            )
            errorState = .networkError
        }
    }

    private func applySuccess(usage: CodexUsageResponse) {
        updateUI(from: usage)
        errorState = .none
        lastAPIError = nil
        lastUpdate = Date()
        if currentSpeed == .slow {
            currentSpeed = .normal
        }
        retryAfterDate = nil
        consecutiveRateLimits = 0
        WidgetReloader.scheduleReload()
        evaluateNotifications()
    }

    private func updateUI(from usage: CodexUsageResponse) {
        lastUsage = usage
        credits = usage.credits
        limitReached = usage.isLimitReached
        additionalLimits = usage.additionalRateLimits
        // The payload's plan wins; the JWT claim only covers an offline start.
        let resolved = CodexPlanType(rawPlan: usage.planType)
        planType = resolved == .unknown ? authState.planType : resolved
        applyWindows(from: usage)
    }

    private func applyWindows(from usage: CodexUsageResponse) {
        windows = CodexWindowResolver.windows(
            in: usage,
            margin: Double(pacingMargin),
            schedule: pacingSchedule
        )
    }

    private func resetState() {
        windows = []
        credits = nil
        planType = .unknown
        limitReached = false
        additionalLimits = []
        lastUsage = nil
        lastUpdate = nil
        lastAPIError = nil
        errorState = .none
        hasConfig = false
    }

    private func notifyTokenExpired() {
        guard let toggles = notifTogglesProvider?() else { return }
        notificationService.notifyCodexTokenExpired(toggles: toggles)
    }

    private func evaluateNotifications() {
        guard let toggles = notifTogglesProvider?() else { return }
        notificationService.evaluateCodex(windows: windows, toggles: toggles)
    }
}

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

    var pacingMargin: Int = 10

    /// Token that last received a 401/403. Prevents retrying the API with a known-dead token.
    private var lastFailedToken: String?

    private let repository: UsageRepositoryProtocol
    private let notificationService: NotificationServiceProtocol
    private var refreshTask: Task<Void, Never>?

    var proxyConfig: ProxyConfig?

    init(
        repository: UsageRepositoryProtocol = UsageRepository(),
        notificationService: NotificationServiceProtocol = NotificationService()
    ) {
        self.repository = repository
        self.notificationService = notificationService
    }

    func refresh(thresholds: UsageThresholds = .default, force: Bool = false) async {
        // Prevent concurrent refreshes — multiple .task/.onAppear can race
        guard !isLoading else { return }

        // Throttle: skip if a successful refresh happened less than 20s ago (avoids 429)
        if !force, let last = lastUpdate, Date().timeIntervalSince(last) < 20 {
            return
        }

        // Silent keychain read — try to recover token if not configured
        // or if the current one already failed (auto-recovery from Claude Code refresh).
        if !repository.isConfigured || lastFailedToken == repository.currentToken {
            repository.syncKeychainTokenSilently()
            if let currentToken = repository.currentToken, currentToken != lastFailedToken {
                lastFailedToken = nil
                errorState = .none
            }
        }

        guard repository.isConfigured,
              repository.currentToken != lastFailedToken else {
            hasConfig = lastFailedToken != nil
            return
        }
        hasConfig = true
        isLoading = true
        defer { isLoading = false }
        do {
            let usage = try await repository.refreshUsage(proxyConfig: proxyConfig)
            update(from: usage)
            errorState = .none
            lastFailedToken = nil
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
            case .tokenExpired:
                lastFailedToken = repository.currentToken
                errorState = .tokenExpired
            case .keychainLocked:
                errorState = .keychainLocked
            case .httpError(429):
                // Rate limited — silently skip, auto-refresh will retry later
                break
            default:
                errorState = .networkError(error.localizedDescription)
            }
        } catch {
            errorState = .networkError(error.localizedDescription)
        }
    }

    func loadCached() {
        if let cached = repository.cachedUsage {
            update(from: cached.usage)
            lastUpdate = cached.fetchDate
        }
    }

    func reloadConfig(thresholds: UsageThresholds = .default) {
        // Silent keychain read — never triggers macOS password dialog
        repository.syncKeychainTokenSilently()
        lastFailedToken = nil
        errorState = .none
        hasConfig = repository.isConfigured
        loadCached()
        notificationService.requestPermission()
        WidgetReloader.scheduleReload()
        refreshTask?.cancel()
        // Sequential: refresh first, then profile after a delay to avoid 429
        refreshTask = Task {
            await refresh(thresholds: thresholds)
            try? await Task.sleep(for: .seconds(2))
            await refreshProfile()
        }
    }

    func startAutoRefresh(interval: TimeInterval = 30, thresholds: UsageThresholds = .default) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            // Wait first — reloadConfig already triggers an initial refresh
            try? await Task.sleep(for: .seconds(interval))
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(thresholds: thresholds)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
    }

    func testConnection() async -> ConnectionTestResult {
        await repository.testConnection(proxyConfig: proxyConfig)
    }

    func connectAutoDetect() async -> ConnectionTestResult {
        repository.syncKeychainTokenSilently()
        let result = await repository.testConnection(proxyConfig: proxyConfig)
        if result.success {
            hasConfig = true
        }
        return result
    }

    private var lastProfileFetch: Date?

    func refreshProfile() async {
        guard repository.isConfigured else { return }
        // Throttle: profile rarely changes, skip if fetched less than 60s ago
        if let last = lastProfileFetch, Date().timeIntervalSince(last) < 60 { return }
        do {
            let profile = try await repository.fetchProfile(proxyConfig: proxyConfig)
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

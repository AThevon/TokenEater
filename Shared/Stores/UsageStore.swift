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

    var hasError: Bool { errorState != .none }

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

    func refresh(thresholds: UsageThresholds = .default) async {
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
                fiveHour: fiveHourPct,
                sevenDay: sevenDayPct,
                sonnet: sonnetPct,
                thresholds: thresholds
            )
        } catch let error as APIError {
            switch error {
            case .tokenExpired:
                lastFailedToken = repository.currentToken
                errorState = .tokenExpired
            case .keychainLocked:
                errorState = .keychainLocked
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
        refreshTask = Task { await refresh(thresholds: thresholds) }
    }

    func startAutoRefresh(interval: TimeInterval = 60, thresholds: UsageThresholds = .default) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
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

    // MARK: - Private

    private func update(from usage: UsageResponse) {
        fiveHourPct = Int(usage.fiveHour?.utilization ?? 0)
        sevenDayPct = Int(usage.sevenDay?.utilization ?? 0)
        sonnetPct = Int(usage.sevenDaySonnet?.utilization ?? 0)

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

        if let pacing = PacingCalculator.calculate(from: usage) {
            pacingDelta = Int(pacing.delta)
            pacingZone = pacing.zone
            pacingResult = pacing
        }
    }
}

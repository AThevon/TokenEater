import SwiftUI
import WidgetKit

@MainActor
@Observable
final class UsageStore {
    var fiveHourPct: Int = 0
    var sevenDayPct: Int = 0
    var sonnetPct: Int = 0
    var fiveHourReset: String = ""
    var pacingDelta: Int = 0
    var pacingZone: PacingZone = .onTrack
    var pacingResult: PacingResult?
    var lastUpdate: Date?
    var isLoading = false
    var hasError = false
    var hasConfig = false

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
        repository.syncKeychainToken()

        guard repository.isConfigured else {
            hasConfig = false
            return
        }
        hasConfig = true
        isLoading = true
        defer { isLoading = false }
        do {
            let usage = try await repository.refreshUsage(proxyConfig: proxyConfig)
            update(from: usage)
            hasError = false
            lastUpdate = Date()
            WidgetCenter.shared.reloadAllTimelines()
            notificationService.checkThresholds(
                fiveHour: fiveHourPct,
                sevenDay: sevenDayPct,
                sonnet: sonnetPct,
                thresholds: thresholds
            )
        } catch {
            hasError = true
        }
    }

    func loadCached() {
        if let cached = repository.cachedUsage {
            update(from: cached.usage)
            lastUpdate = cached.fetchDate
        }
    }

    func reloadConfig(thresholds: UsageThresholds = .default) {
        repository.syncKeychainToken()
        hasConfig = repository.isConfigured
        loadCached()
        notificationService.requestPermission()
        WidgetCenter.shared.reloadAllTimelines()
        Task { await refresh(thresholds: thresholds) }
    }

    func startAutoRefresh(interval: TimeInterval = 300, thresholds: UsageThresholds = .default) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(thresholds: thresholds)
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
        repository.syncKeychainToken()
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

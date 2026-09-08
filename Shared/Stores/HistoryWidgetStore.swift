import Foundation
import WidgetKit

@MainActor
final class HistoryWidgetStore {
    private let service: SessionHistoryServiceProtocol
    private let sharedFile: SharedFileServiceProtocol
    private let reloadWidget: @MainActor () -> Void
    private var refreshTask: Task<Void, Never>?

    init(
        service: SessionHistoryServiceProtocol = CombinedSessionHistoryService(),
        sharedFile: SharedFileServiceProtocol = SharedFileService(),
        reloadWidget: @escaping @MainActor () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: "HistorySparklineWidget")
        }
    ) {
        self.service = service
        self.sharedFile = sharedFile
        self.reloadWidget = reloadWidget
    }

    deinit { refreshTask?.cancel() }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
    }

    func refresh() async {
        let service = service
        do {
            let buckets = try await Task.detached(priority: .utility) {
                try await service.loadHistory(range: .sevenDays)
            }.value
            try Task.checkCancellation()
            let now = Date()
            let totals = MonitoringInsightsStore.dailyTotalsByDay(from: buckets, today: now)
            let changed = sharedFile.lastWeekDailyTotals != totals
                || sharedFile.lastWeekTotalsRefreshedAt.map { !Calendar.current.isDate($0, inSameDayAs: now) } != false
            sharedFile.updateLastWeekDailyTotals(totals, refreshedAt: now)
            if changed { reloadWidget() }
        } catch {
            return
        }
    }
}

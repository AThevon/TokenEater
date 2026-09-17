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

    /// Matches the sparkline widget's own timeline policy. Writing more often
    /// than WidgetKit reads is pure cost: every pass re-parses the whole
    /// session tree for both providers, and this repo has shipped an idle-CPU
    /// regression before (#255).
    private static let refreshInterval: Duration = .seconds(300)

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: Self.refreshInterval) }
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
            // Only touch the shared file when something actually moved. The
            // write is a coordinated atomic replace that every other reader
            // contends with, and an unchanged rewrite buys nothing.
            guard changed else { return }
            sharedFile.updateLastWeekDailyTotals(totals, refreshedAt: now)
            reloadWidget()
        } catch {
            return
        }
    }
}

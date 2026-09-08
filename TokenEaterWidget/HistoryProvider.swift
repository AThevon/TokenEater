import Foundation
import WidgetKit

struct HistoryProvider: TimelineProvider {
    private let sharedFile = SharedFileService()

    func placeholder(in context: Context) -> UsageEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(context.isPreview ? .placeholder : fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        completion(Timeline(entries: [fetchEntry()], policy: .after(Date().addingTimeInterval(300))))
    }

    private func fetchEntry() -> UsageEntry {
        sharedFile.invalidateCache()
        WidgetTheme.invalidate()
        return UsageEntry(
            date: Date(), usage: nil,
            lastSync: sharedFile.lastWeekTotalsRefreshedAt,
            lastWeekDailyTotals: sharedFile.lastWeekDailyTotals
        )
    }
}

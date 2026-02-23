import WidgetKit
import Foundation

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = fetchEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func fetchEntry() -> UsageEntry {
        guard SharedContainer.isConfigured else {
            return .unconfigured
        }

        if let cached = SharedContainer.cachedUsage {
            let isStale: Bool
            if let lastSync = SharedContainer.lastSyncDate {
                isStale = Date().timeIntervalSince(lastSync) > 600
            } else {
                isStale = true
            }
            return UsageEntry(
                date: Date(),
                usage: cached.usage,
                isStale: isStale
            )
        }

        return UsageEntry(date: Date(), usage: nil, error: String(localized: "error.nodata"))
    }
}

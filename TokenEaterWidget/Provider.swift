import WidgetKit
import Foundation

struct Provider: TimelineProvider {
    private let sharedFile = SharedFileService()

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
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)

        if entry.wasJustRefreshed {
            // Show "Refreshed" for 10 seconds, then switch to normal display
            let normalEntry = UsageEntry(
                date: Date().addingTimeInterval(10),
                usage: entry.usage,
                error: entry.error,
                isStale: entry.isStale,
                wasJustRefreshed: false
            )
            completion(Timeline(entries: [entry, normalEntry], policy: .after(nextUpdate)))
        } else {
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func fetchEntry() -> UsageEntry {
        guard sharedFile.isConfigured else {
            return .unconfigured
        }

        let lastRefreshError = sharedFile.lastRefreshError

        if let cached = sharedFile.cachedUsage {
            let isStale: Bool
            let wasJustRefreshed: Bool
            if let lastSync = sharedFile.lastSyncDate {
                isStale = Date().timeIntervalSince(lastSync) > 120
                wasJustRefreshed = lastRefreshError == nil && Date().timeIntervalSince(lastSync) < 15
            } else {
                isStale = true
                wasJustRefreshed = false
            }
            return UsageEntry(
                date: Date(),
                usage: cached.usage,
                error: lastRefreshError,
                isStale: isStale,
                wasJustRefreshed: wasJustRefreshed
            )
        }

        return UsageEntry(date: Date(), usage: nil, error: lastRefreshError ?? String(localized: "error.nodata"))
    }
}

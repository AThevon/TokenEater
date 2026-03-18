import WidgetKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app.widget", category: "Provider")

struct StaticProvider: TimelineProvider {
    private let sharedFile = SharedFileService()

    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
        } else {
            completion(fetchEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = fetchEntry()
        // Re-request timeline after 5 minutes — WidgetKit will call getTimeline again
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func fetchEntry() -> UsageEntry {
        sharedFile.invalidateCache()
        logger.info("fetchEntry: fileURL=\(self.sharedFile.fileURL.path, privacy: .public), isConfigured=\(self.sharedFile.isConfigured)")
        guard sharedFile.isConfigured else {
            logger.error("Widget: not configured")
            return .unconfigured
        }

        if let cached = sharedFile.cachedUsage {
            let lastSync = sharedFile.lastSyncDate
            let isStale: Bool
            if let lastSync {
                isStale = Date().timeIntervalSince(lastSync) > 120
            } else {
                isStale = true
            }
            return UsageEntry(
                date: Date(),
                usage: cached.usage,
                isStale: isStale,
                lastSync: lastSync
            )
        }

        return UsageEntry(date: Date(), usage: nil, error: String(localized: "error.nodata"))
    }
}

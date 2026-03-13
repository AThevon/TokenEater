import WidgetKit
import AppIntents
import Foundation

struct Provider: AppIntentTimelineProvider {
    private let sharedFile = SharedFileService()

    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func snapshot(for configuration: RefreshWidgetIntent, in context: Context) async -> UsageEntry {
        if context.isPreview {
            return .placeholder
        }
        return fetchEntry()
    }

    func timeline(for configuration: RefreshWidgetIntent, in context: Context) async -> Timeline<UsageEntry> {
        let entry = fetchEntry()
        // .atEnd tells WidgetKit to call timeline() again as soon as the current entry expires.
        // More aggressive than .after(date) — ensures frequent re-reads of the shared file.
        return Timeline(entries: [entry], policy: .atEnd)
    }

    private func fetchEntry() -> UsageEntry {
        sharedFile.invalidateCache()
        guard sharedFile.isConfigured else {
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

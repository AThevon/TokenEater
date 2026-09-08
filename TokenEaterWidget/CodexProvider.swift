import WidgetKit
import Foundation

struct CodexProvider: TimelineProvider {
    private let sharedFile = CodexSharedFileService()

    func placeholder(in context: Context) -> CodexEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (CodexEntry) -> Void) {
        completion(context.isPreview ? .placeholder : fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexEntry>) -> Void) {
        let entry = fetchEntry()
        completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(300))))
    }

    private func fetchEntry() -> CodexEntry {
        sharedFile.invalidateCache()
        WidgetTheme.invalidate()
        let now = Date()
        let exists = FileManager.default.fileExists(atPath: sharedFile.fileURL.path)
        let cached = sharedFile.cachedUsage
        let lastSync = sharedFile.lastSyncDate
        return CodexEntry(
            date: now, usage: cached?.usage,
            isEnabled: !exists || sharedFile.isEnabled,
            isStale: lastSync.map { now.timeIntervalSince($0) > 900 } ?? true,
            lastSync: lastSync,
            error: cached == nil ? String(localized: "error.nodata") : nil,
            pacingMargin: sharedFile.pacingMargin
        )
    }
}

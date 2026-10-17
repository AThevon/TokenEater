import WidgetKit
import Foundation

/// Timelines for the "Claude · Account" widget. Reads only the shared folder:
/// the accounts index and the theme from `shared.json`, the numbers from the
/// chosen account's own file (`shared.json` for the main account,
/// `shared-acct-<uuid>.json` for an added one). Same refresh policy as the
/// other Claude widgets: the app reloads it on every change, and WidgetKit
/// asks again after five minutes.
struct ClaudeAccountProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ClaudeAccountEntry {
        .placeholder
    }

    func snapshot(for configuration: SelectClaudeAccountIntent, in context: Context) async -> ClaudeAccountEntry {
        context.isPreview ? .placeholder : fetchEntry(for: configuration)
    }

    func timeline(for configuration: SelectClaudeAccountIntent, in context: Context) async -> Timeline<ClaudeAccountEntry> {
        let entry = fetchEntry(for: configuration)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func fetchEntry(for configuration: SelectClaudeAccountIntent) -> ClaudeAccountEntry {
        // The views read theme, thresholds, Smart Color and the pacing
        // schedule through WidgetTheme, from `shared.json` whatever the
        // account: they are the app's settings, not the account's.
        WidgetTheme.invalidate()
        let mainFile = SharedFileService()
        let state = ClaudeAccountEntryState.resolve(id: configuration.account?.id, index: mainFile.accountsIndex)
        guard let fileName = state.sharedFileName else { return .removed }

        let isMain = state.entry?.isMain == true
        let file = isMain ? mainFile : SharedFileService(fileName: fileName)
        let now = Date()
        guard let cached = file.cachedUsage else {
            // The main account with nothing cached says what the other Claude
            // widgets say; an added one is waiting for its first refresh.
            let error = isMain ? UsageEntry.unconfigured.error : nil
            return ClaudeAccountEntry(date: now, state: state, usage: UsageEntry(date: now, usage: nil, error: error))
        }
        let lastSync = file.lastSyncDate
        let isStale = lastSync.map { now.timeIntervalSince($0) > 900 } ?? true
        return ClaudeAccountEntry(
            date: now,
            state: state,
            usage: UsageEntry(date: now, usage: cached.usage, isStale: isStale, lastSync: lastSync)
        )
    }
}

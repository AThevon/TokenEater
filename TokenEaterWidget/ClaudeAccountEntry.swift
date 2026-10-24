import WidgetKit
import Foundation

/// One render of the "Claude · Account" widget: the account it was configured
/// with, where that account stands, and its numbers in the shape the real
/// widget views already read.
struct ClaudeAccountEntry: TimelineEntry {
    let date: Date
    let state: ClaudeAccountEntryState
    let usage: UsageEntry

    var accountName: String? { state.entry?.name }
    var colorHex: String? { state.entry?.colorHex }

    /// The widget gallery's preview: the main account, sample numbers.
    static var placeholder: ClaudeAccountEntry {
        ClaudeAccountEntry(date: Date(), state: .active(.mainFallback), usage: .placeholder)
    }

    /// The account the widget was set to is no longer tracked.
    static var removed: ClaudeAccountEntry {
        ClaudeAccountEntry(date: Date(), state: .removed, usage: UsageEntry(date: Date(), usage: nil))
    }
}

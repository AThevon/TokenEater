import WidgetKit
import Foundation

/// Centralized, debounced widget timeline reloader.
/// Uses targeted reloadTimelines(ofKind:) for each widget kind
/// to avoid exhausting the shared reload budget.
@MainActor
enum WidgetReloader {
    static let usageKind = "TokenEaterWidget"
    static let codexUsageKind = "CodexUsageWidget"
    static let pacingKind = "PacingWidget"
    /// The "Claude · Account" widget, where the user picks the account in
    /// Edit Widget. Frozen like every other kind once it ships.
    static let accountKind = "ClaudeAccountWidget"

    private static var pending: DispatchWorkItem?
    private static var pendingAccount: DispatchWorkItem?

    /// Request a widget timeline reload for all widget kinds.
    /// Multiple calls within `delay` seconds are coalesced into one.
    static func scheduleReload(delay: TimeInterval = 0.5) {
        pending?.cancel()
        // The account widget is reloaded below with the rest: a reload of it
        // alone still waiting would be a second one for nothing.
        pendingAccount?.cancel()
        pendingAccount = nil
        let item = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: usageKind)
            WidgetCenter.shared.reloadTimelines(ofKind: pacingKind)
            WidgetCenter.shared.reloadTimelines(ofKind: codexUsageKind)
            WidgetCenter.shared.reloadTimelines(ofKind: accountKind)
        }
        pending = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + delay,
            execute: item
        )
    }

    /// Reloads only the account widget: an added account's numbers changed,
    /// or the account list did. No other kind reads either, so their budget
    /// is left alone. Coalesced like `scheduleReload`.
    static func scheduleAccountReload(delay: TimeInterval = 0.5) {
        pendingAccount?.cancel()
        let item = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: accountKind)
        }
        pendingAccount = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + delay,
            execute: item
        )
    }
}

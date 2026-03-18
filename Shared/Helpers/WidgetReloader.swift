import WidgetKit
import Foundation

/// Centralized, debounced widget timeline reloader.
/// Uses targeted reloadTimelines(ofKind:) for each widget kind
/// to avoid exhausting the shared reload budget.
@MainActor
enum WidgetReloader {
    static let usageKind = "TokenEaterWidget"
    static let pacingKind = "PacingWidget"

    private static var pending: DispatchWorkItem?

    /// Request a widget timeline reload for all widget kinds.
    /// Multiple calls within `delay` seconds are coalesced into one.
    static func scheduleReload(delay: TimeInterval = 0.5) {
        pending?.cancel()
        let item = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: usageKind)
            WidgetCenter.shared.reloadTimelines(ofKind: pacingKind)
        }
        pending = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + delay,
            execute: item
        )
    }
}

import WidgetKit
import Foundation

/// Centralized, debounced widget timeline reloader.
/// Coalesces rapid-fire calls and runs off the main thread
/// to prevent blocking the UI — especially important for
/// ad-hoc signed builds where WidgetCenter XPC may behave
/// differently than dev-signed builds.
@MainActor
enum WidgetReloader {
    private static var pending: DispatchWorkItem?

    /// Request a widget timeline reload.
    /// Multiple calls within `delay` seconds are coalesced into one.
    static func scheduleReload(delay: TimeInterval = 0.5) {
        pending?.cancel()
        let item = DispatchWorkItem {
            WidgetCenter.shared.reloadAllTimelines()
        }
        pending = item
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + delay,
            execute: item
        )
    }
}

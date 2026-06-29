import Foundation

/// Overlay-domain slice of the user settings. Extracted from SettingsStore as
/// part of the fat-store split, same pattern as `PacingSettingsStore` and
/// `NotificationSettingsStore`. Owns the Agent Watchers overlay configuration
/// (enable, dock effect, scale, side, trigger zone) plus the watcher rendering
/// preferences and the single performance toggle. Each property persists itself
/// to UserDefaults. No shared-file mirror: the widget doesn't render the overlay.
///
/// Property names keep their historic `overlay*` / `watcher*` prefixes so the
/// backwards-compatible forwards on SettingsStore stay 1:1 and the prefix keeps
/// its meaning at call sites.
@MainActor
final class OverlaySettingsStore: ObservableObject {
    @Published var overlayEnabled: Bool {
        didSet { UserDefaults.standard.set(overlayEnabled, forKey: "overlayEnabled") }
    }
    @Published var overlayDockEffect: Bool {
        didSet { UserDefaults.standard.set(overlayDockEffect, forKey: "overlayDockEffect") }
    }
    @Published var overlayScale: Double {
        didSet { UserDefaults.standard.set(overlayScale, forKey: "overlayScale") }
    }
    @Published var overlayLeftSide: Bool {
        didSet { UserDefaults.standard.set(overlayLeftSide, forKey: "overlayLeftSide") }
    }
    @Published var overlayTriggerZone: OverlayTriggerZone {
        didSet { UserDefaults.standard.set(overlayTriggerZone.rawValue, forKey: "overlayTriggerZone") }
    }
    @Published var watchersDetailedMode: Bool {
        didSet { UserDefaults.standard.set(watchersDetailedMode, forKey: "watchersDetailedMode") }
    }
    @Published var watcherStyle: WatcherStyle {
        didSet { UserDefaults.standard.set(watcherStyle.rawValue, forKey: "watcherStyle") }
    }
    @Published var watcherDisplayMode: WatcherDisplayMode {
        didSet { UserDefaults.standard.set(watcherDisplayMode.rawValue, forKey: "watcherDisplayMode") }
    }
    @Published var watcherScanInterval: WatcherScanInterval {
        didSet { UserDefaults.standard.set(watcherScanInterval.rawValue, forKey: "watcherScanInterval") }
    }
    @Published var watcherVisibility: WatcherVisibility {
        didSet { UserDefaults.standard.set(watcherVisibility.rawValue, forKey: "watcherVisibility") }
    }

    // Performance
    @Published var watcherAnimationsEnabled: Bool {
        didSet { UserDefaults.standard.set(watcherAnimationsEnabled, forKey: "watcherAnimationsEnabled") }
    }

    init() {
        // Defaults below apply only on first launch (no value yet in
        // UserDefaults) - per the `as? T ?? default` reads.
        self.overlayEnabled = UserDefaults.standard.object(forKey: "overlayEnabled") as? Bool ?? true
        self.overlayDockEffect = UserDefaults.standard.object(forKey: "overlayDockEffect") as? Bool ?? true
        self.overlayScale = UserDefaults.standard.object(forKey: "overlayScale") as? Double ?? 1.1
        self.overlayLeftSide = UserDefaults.standard.bool(forKey: "overlayLeftSide")
        self.overlayTriggerZone = OverlayTriggerZone(
            rawValue: UserDefaults.standard.string(forKey: "overlayTriggerZone") ?? "medium"
        ) ?? .medium
        self.watchersDetailedMode = UserDefaults.standard.object(forKey: "watchersDetailedMode") as? Bool ?? true
        self.watcherStyle = WatcherStyle(
            rawValue: UserDefaults.standard.string(forKey: "watcherStyle") ?? "frost"
        ) ?? .frost
        self.watcherDisplayMode = WatcherDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "watcherDisplayMode") ?? "branchPriority"
        ) ?? .branchPriority
        self.watcherScanInterval = (UserDefaults.standard.object(forKey: "watcherScanInterval") as? Int)
            .flatMap(WatcherScanInterval.init(rawValue:)) ?? .twoSeconds
        self.watcherVisibility = (UserDefaults.standard.object(forKey: "watcherVisibility") as? Int)
            .flatMap(WatcherVisibility.init(rawValue:)) ?? .thirtyMinutes
        self.watcherAnimationsEnabled = UserDefaults.standard.object(forKey: "watcherAnimationsEnabled") as? Bool ?? true
    }
}

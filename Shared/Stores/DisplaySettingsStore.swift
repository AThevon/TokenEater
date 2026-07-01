import Foundation

/// Display / menu-bar domain slice of the user settings. Extracted from
/// SettingsStore as part of the fat-store split, same pattern as
/// `PacingSettingsStore`, `NotificationSettingsStore`, and `OverlaySettingsStore`.
///
/// Owns the menu-bar visibility + style, the pinned metrics set, the reset /
/// pacing display formats, the smart-color settings (with the shared-file mirror
/// the sandboxed widget reads), the glow intensity, the menu-bar text colors,
/// and the popover satellite toggles. Each property persists itself to
/// UserDefaults; smart-color also mirrors to the shared file (so the widget
/// colors identically), which is why this store needs `sharedFileService`.
@MainActor
final class DisplaySettingsStore: ObservableObject {
    @Published var showMenuBar: Bool {
        didSet { UserDefaults.standard.set(showMenuBar, forKey: "showMenuBar") }
    }
    /// When true, the app starts in the menu bar only and skips auto-opening the
    /// dashboard window at launch (incl. at login). The window stays reachable
    /// from the menu bar (right-click > Open). Onboarding always force-opens
    /// regardless of this flag so a fresh install is never left with no UI (#198).
    @Published var launchInBackground: Bool {
        didSet { UserDefaults.standard.set(launchInBackground, forKey: "launchInBackground") }
    }
    @Published var pinnedMetrics: Set<MetricID> {
        didSet {
            UserDefaults.standard.set(pinnedMetrics.map(\.rawValue), forKey: "pinnedMetrics")
        }
    }
    @Published var resetDisplayFormat: ResetDisplayFormat {
        didSet { UserDefaults.standard.set(resetDisplayFormat.rawValue, forKey: "resetDisplayFormat") }
    }
    /// Global "Smart Color" theming. When ON, color codes throughout the app
    /// (gauges, reset countdowns) integrate the time-to-reset factor instead of
    /// raw thresholds. Example: 95% utilization with 2 minutes left to reset
    /// stays green rather than going red. Falls back to threshold-based coloring
    /// when no reset date is available.
    @Published var smartColorEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smartColorEnabled, forKey: "smartColorEnabled")
            sharedFileService.updateSmartColorEnabled(smartColorEnabled)
        }
    }
    /// User-selected temperament for the smart color algorithm. Shifts
    /// when the gauge transitions from chill -> warning -> hot. See
    /// `SmartColorProfile` for the parameter mapping.
    @Published var smartColorProfile: SmartColorProfile {
        didSet {
            UserDefaults.standard.set(smartColorProfile.rawValue, forKey: "smartColorProfile")
            sharedFileService.updateSmartColorProfile(smartColorProfile)
        }
    }
    /// Controls the global glow / halo intensity in the popover and monitoring
    /// views. Drives a single environment value read by every `.dsGlow()` call.
    @Published var glowIntensity: DS.GlowIntensity {
        didSet { UserDefaults.standard.set(glowIntensity.rawValue, forKey: "glowIntensity") }
    }
    /// Typography / separator style for the pinned metrics in the menu bar.
    @Published var menuBarStyle: MenuBarStyle {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
    }
    /// Glyph used for the pacing indicator across menu bar + popover.
    @Published var pacingShape: PacingShape {
        didSet { UserDefaults.standard.set(pacingShape.rawValue, forKey: "pacingShape") }
    }
    @Published var sessionPacingDisplayMode: PacingDisplayMode {
        didSet { UserDefaults.standard.set(sessionPacingDisplayMode.rawValue, forKey: "sessionPacingDisplayMode") }
    }
    @Published var weeklyPacingDisplayMode: PacingDisplayMode {
        didSet { UserDefaults.standard.set(weeklyPacingDisplayMode.rawValue, forKey: "weeklyPacingDisplayMode") }
    }
    /// Hex string ("#RRGGBB") for the menu-bar reset countdown text.
    /// Empty = use the system's primary label color.
    @Published var resetTextColorHex: String {
        didSet { UserDefaults.standard.set(resetTextColorHex, forKey: "resetTextColorHex") }
    }
    /// Hex string ("#RRGGBB") for the "5h" / "7d" / "S" period label.
    /// Empty = use the system's tertiary label color.
    @Published var sessionPeriodColorHex: String {
        didSet { UserDefaults.standard.set(sessionPeriodColorHex, forKey: "sessionPeriodColorHex") }
    }
    /// Controls whether the Sonnet satellite appears in the popover Classic
    /// variant AND in the dashboard constellation. The menu-bar visibility of
    /// Sonnet is driven by `pinnedMetrics.contains(.sonnet)`, independently.
    @Published var displaySonnet: Bool {
        didSet { UserDefaults.standard.set(displaySonnet, forKey: "displaySonnet") }
    }
    /// Same as `displaySonnet` but for Claude Design.
    @Published var displayDesign: Bool {
        didSet { UserDefaults.standard.set(displayDesign, forKey: "displayDesign") }
    }
    /// Same as `displayDesign` but for the paid Extra Credits pool. Only
    /// surfaced in settings when `UsageStore.hasExtraCredits` is true.
    @Published var displayExtraCredits: Bool {
        didSet { UserDefaults.standard.set(displayExtraCredits, forKey: "displayExtraCredits") }
    }

    private let sharedFileService: SharedFileServiceProtocol

    init(sharedFileService: SharedFileServiceProtocol) {
        self.sharedFileService = sharedFileService

        self.showMenuBar = UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true
        self.launchInBackground = SettingsDefaults.bool(key: "launchInBackground", default: false)

        self.resetDisplayFormat = ResetDisplayFormat(
            rawValue: UserDefaults.standard.string(forKey: "resetDisplayFormat") ?? "relative"
        ) ?? .relative
        self.resetTextColorHex = UserDefaults.standard.string(forKey: "resetTextColorHex") ?? ""
        self.sessionPeriodColorHex = UserDefaults.standard.string(forKey: "sessionPeriodColorHex") ?? ""

        // Default ON. Migration: if the user had explicitly set the legacy
        // "smartResetColor" key, respect that decision; otherwise opt them into
        // smart coloring globally.
        let initialSmartColor: Bool = {
            if let v = UserDefaults.standard.object(forKey: "smartColorEnabled") as? Bool { return v }
            if let legacy = UserDefaults.standard.object(forKey: "smartResetColor") as? Bool { return legacy }
            return true
        }()
        self.smartColorEnabled = initialSmartColor
        // Push the resolved value to the shared file so the (sandboxed) widget
        // sees the same setting on first launch without waiting for a toggle.
        sharedFileService.updateSmartColorEnabled(initialSmartColor)
        let initialProfile = SmartColorProfile(
            rawValue: UserDefaults.standard.string(forKey: "smartColorProfile") ?? SmartColorProfile.default.rawValue
        ) ?? .default
        self.smartColorProfile = initialProfile
        // Mirror the resolved profile to the shared file so the (sandboxed)
        // widget picks it up at first paint without waiting for a toggle.
        sharedFileService.updateSmartColorProfile(initialProfile)
        self.glowIntensity = DS.GlowIntensity(
            rawValue: UserDefaults.standard.string(forKey: "glowIntensity") ?? DS.GlowIntensity.glow.rawValue
        ) ?? .glow
        self.menuBarStyle = MenuBarStyle(
            rawValue: UserDefaults.standard.string(forKey: "menuBarStyle") ?? "classic"
        ) ?? .classic
        self.pacingShape = PacingShape(
            rawValue: UserDefaults.standard.string(forKey: "pacingShape") ?? "circle"
        ) ?? .circle

        // Migrate the legacy global `pacingDisplayMode` into the two per-bucket
        // settings so existing users keep the mode they had. If either per-bucket
        // value has been saved before, prefer it.
        let legacyMode = PacingDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "pacingDisplayMode") ?? "dotDelta"
        ) ?? .dotDelta
        self.sessionPacingDisplayMode = PacingDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "sessionPacingDisplayMode") ?? legacyMode.rawValue
        ) ?? legacyMode
        self.weeklyPacingDisplayMode = PacingDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "weeklyPacingDisplayMode") ?? legacyMode.rawValue
        ) ?? legacyMode

        var legacyPinned: Set<MetricID>
        if let saved = UserDefaults.standard.stringArray(forKey: "pinnedMetrics") {
            // Migrate legacy "pacing" (covered weekly only) to the explicit weeklyPacing id.
            let normalized = saved.map { $0 == "pacing" ? "weeklyPacing" : $0 }
            legacyPinned = Set(normalized.compactMap { MetricID(rawValue: $0) })
        } else {
            legacyPinned = [.fiveHour, .sevenDay]
        }
        // Migrate the old `showSessionReset` boolean into the new `.sessionReset`
        // pinnable metric so existing users keep seeing the countdown they opted
        // in to.
        if UserDefaults.standard.object(forKey: "showSessionReset") != nil,
           UserDefaults.standard.bool(forKey: "showSessionReset") {
            legacyPinned.insert(.sessionReset)
        }
        self.pinnedMetrics = legacyPinned

        // displaySonnet and displayDesign default to false for everyone -
        // the satellites are opt-in. Users who had the old behaviour (sonnet
        // pinned automatically toggled displaySonnet to true) keep whatever
        // they had saved.
        if UserDefaults.standard.object(forKey: "displaySonnet") != nil {
            self.displaySonnet = UserDefaults.standard.bool(forKey: "displaySonnet")
        } else {
            self.displaySonnet = false
        }
        self.displayDesign = UserDefaults.standard.object(forKey: "displayDesign") != nil
            ? UserDefaults.standard.bool(forKey: "displayDesign")
            : false
        self.displayExtraCredits = UserDefaults.standard.object(forKey: "displayExtraCredits") != nil
            ? UserDefaults.standard.bool(forKey: "displayExtraCredits")
            : false
    }
}

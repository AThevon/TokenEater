import Foundation

/// Top-level navigation in the window app. Four spaces -> Stats (dashboard),
/// History (JSONL usage over time), Studio (all visual customization),
/// Settings (behavioral configuration).
enum AppSpace: String, CaseIterable {
    case monitoring
    case history
    case studio
    case settings

    var labelKey: String {
        switch self {
        case .monitoring: "sidebar.monitoring"
        case .history:    "sidebar.history"
        case .studio:     "sidebar.studio"
        case .settings:   "sidebar.settings"
        }
    }

    var label: String { String(localized: String.LocalizationValue(labelKey)) }

    var iconName: String {
        switch self {
        case .monitoring: "gauge.high"
        case .history:    "clock.arrow.circlepath"
        case .studio:     "wand.and.stars"
        case .settings:   "gearshape.fill"
        }
    }
}

/// Sub-sections inside the Settings space -> behavioral configuration only.
/// The visual customization screens (popover / menu bar / themes) live in
/// the Studio space since 5.9. Order drives the sub-sidebar display.
enum SettingsSection: String, CaseIterable {
    case general
    case pacing
    case agentWatchers
    case notifications

    var labelKey: String {
        switch self {
        case .general:       "sidebar.general"
        case .pacing:        "sidebar.pacing"
        case .agentWatchers: "sidebar.agentWatchers"
        case .notifications: "sidebar.notifications"
        }
    }

    var label: String { String(localized: String.LocalizationValue(labelKey)) }

    var iconName: String {
        switch self {
        case .general:       "slider.horizontal.3"
        case .pacing:        "speedometer"
        case .agentWatchers: "waveform.path.ecg"
        case .notifications: "bell.fill"
        }
    }
}

/// Surfaces inside the Studio space -> one per customizable surface of the
/// app. Order drives the switcher strip display.
enum StudioSection: String, CaseIterable {
    case popover
    case menuBar
    case themes

    var labelKey: String {
        switch self {
        case .popover: "studio.surface.popover"
        case .menuBar: "studio.surface.menuBar"
        case .themes:  "studio.surface.themes"
        }
    }

    var hintKey: String { labelKey + ".hint" }

    var label: String { String(localized: String.LocalizationValue(labelKey)) }
    var hint: String { String(localized: String.LocalizationValue(hintKey)) }

    var iconName: String {
        switch self {
        case .popover: "menubar.dock.rectangle"
        case .menuBar: "menubar.rectangle"
        case .themes:  "paintpalette.fill"
        }
    }
}

/// Parsed navigation target sent via `Notification.Name.navigateToSection`.
/// Legacy string payloads (`display`, `themes`, ...) are mapped to their new
/// equivalents so older call sites keep working while we migrate.
struct NavigationTarget: Equatable {
    let space: AppSpace
    let settingsSection: SettingsSection?
    let studioSection: StudioSection?

    init(
        space: AppSpace,
        settingsSection: SettingsSection? = nil,
        studioSection: StudioSection? = nil
    ) {
        self.space = space
        self.settingsSection = settingsSection
        self.studioSection = studioSection
    }

    /// Historical spellings of the customization screens that moved from
    /// Settings to the Studio space. Old deep links and persisted payloads
    /// must keep landing on the right editor.
    private static let legacyStudioAliases: [String: StudioSection] = [
        "themes": .themes,
        "settings.themes": .themes,
        "display": .menuBar,
        "settings.display": .menuBar,
        "popover": .popover,
        "settings.popover": .popover,
    ]

    /// Parse from a legacy or new-style payload string. Recognised values :
    /// - `"monitoring"`, `"history"`, `"studio"`, `"settings"` -> AppSpace only
    /// - `"studio.popover"`, `"studio.menuBar"`, `"studio.themes"` -> Studio surface
    /// - `"settings.general"`, `"settings.pacing"`, ... -> settings sub-section
    /// - legacy `"dashboard"`, `"stats"` -> `.monitoring` (migration shims)
    /// - legacy `"display"` / `"themes"` / `"popover"` (flat or `settings.`
    ///   prefixed) -> the matching Studio surface
    static func parse(_ payload: String) -> NavigationTarget? {
        // Legacy aliases that pre-date the rename to `.monitoring`.
        if payload == "dashboard" || payload == "stats" {
            return NavigationTarget(space: .monitoring)
        }
        // Customization screens that used to live under Settings.
        if let surface = legacyStudioAliases[payload] {
            return NavigationTarget(space: .studio, studioSection: surface)
        }
        // Nested "studio.xxx" form.
        if payload.hasPrefix("studio.") {
            let sub = String(payload.dropFirst("studio.".count))
            if sub.isEmpty { return NavigationTarget(space: .studio) }
            if let surface = StudioSection(rawValue: sub) {
                return NavigationTarget(space: .studio, studioSection: surface)
            }
            return nil
        }
        // Nested "settings.xxx" form.
        if payload.hasPrefix("settings.") {
            let sub = String(payload.dropFirst("settings.".count))
            if sub.isEmpty { return NavigationTarget(space: .settings) }
            if let section = SettingsSection(rawValue: sub) {
                return NavigationTarget(space: .settings, settingsSection: section)
            }
            return nil
        }
        // Top-level space.
        if let space = AppSpace(rawValue: payload) {
            return NavigationTarget(space: space)
        }
        // Legacy flat settings sub-section names.
        if let section = SettingsSection(rawValue: payload) {
            return NavigationTarget(space: .settings, settingsSection: section)
        }
        return nil
    }
}

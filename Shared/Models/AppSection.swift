import Foundation

/// Top-level navigation in the window app. Three spaces -> Stats (dashboard),
/// History (JSONL usage over time), Settings (all configuration).
enum AppSpace: String, CaseIterable {
    case monitoring
    case history
    case settings

    var labelKey: String {
        switch self {
        case .monitoring: "sidebar.monitoring"
        case .history:    "sidebar.history"
        case .settings:   "sidebar.settings"
        }
    }

    var label: String { String(localized: String.LocalizationValue(labelKey)) }

    var iconName: String {
        switch self {
        case .monitoring: "gauge.high"
        case .history:    "clock.arrow.circlepath"
        case .settings:   "gearshape.fill"
        }
    }
}

/// Sub-sections inside the Settings space. Every configuration screen lives
/// here -> general preferences first, then display / themes / popover /
/// agent watchers / performance. Order drives the sub-sidebar display.
enum SettingsSection: String, CaseIterable {
    case general
    case themes
    case display
    case popover
    case agentWatchers
    case performance

    var labelKey: String {
        switch self {
        case .general:       "sidebar.general"
        case .display:       "sidebar.display"
        case .themes:        "sidebar.themes"
        case .popover:       "sidebar.popover"
        case .agentWatchers: "sidebar.agentWatchers"
        case .performance:   "sidebar.performance"
        }
    }

    var label: String { String(localized: String.LocalizationValue(labelKey)) }

    var iconName: String {
        switch self {
        case .general:       "slider.horizontal.3"
        case .display:       "menubar.rectangle"
        case .themes:        "paintpalette.fill"
        case .popover:       "menubar.dock.rectangle"
        case .agentWatchers: "waveform.path.ecg"
        case .performance:   "speedometer"
        }
    }
}

/// Parsed navigation target sent via `Notification.Name.navigateToSection`.
/// Legacy string payloads (`display`, `themes`, ...) are mapped to their new
/// settings-sub-section equivalents so older call sites keep working while we
/// migrate.
struct NavigationTarget: Equatable {
    let space: AppSpace
    let settingsSection: SettingsSection?

    init(space: AppSpace, settingsSection: SettingsSection? = nil) {
        self.space = space
        self.settingsSection = settingsSection
    }

    /// Parse from a legacy or new-style payload string. Recognised values :
    /// - `"monitoring"`, `"history"`, `"settings"` -> AppSpace only
    /// - `"settings.general"`, `"settings.display"`, ... -> space + sub-section
    /// - legacy `"dashboard"`, `"stats"` -> `.monitoring` (migration shims)
    /// - legacy `"display"`, `"themes"`, `"popover"`, `"agentWatchers"`,
    ///   `"performance"` -> `.settings` space + matching sub-section
    static func parse(_ payload: String) -> NavigationTarget? {
        // Legacy aliases that pre-date the rename to `.monitoring`.
        if payload == "dashboard" || payload == "stats" {
            return NavigationTarget(space: .monitoring)
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

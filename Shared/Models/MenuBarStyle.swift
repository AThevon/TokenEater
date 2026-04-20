import Foundation

/// Controls the typography, labels and separators of the pinned metrics
/// rendered into the menu bar icon. Purely presentational - doesn't affect
/// which metrics are shown (that's `pinnedMetrics`) or their values.
enum MenuBarStyle: String, Codable, CaseIterable, Identifiable {
    case classic  // SF system, short labels + space separators, weights vary
    case mono     // SF Mono, labels inline with `:` (e.g. 5h:26), tight
    case badge    // each metric in a rounded tinted pill with matching text

    var id: String { rawValue }

    var localizedLabel: String {
        NSLocalizedString("menuBarStyle.\(rawValue)", comment: "")
    }
}

import Foundation

/// LEGACY (pre-5.10). The single global menu bar style was replaced by the
/// composable menu bar's per-segment styles (`MenuBarSegmentStyle`). This enum
/// survives only as a decoding target for the stored `menuBarStyle` key that
/// `MenuBarConfigMigrator` reads once. No UI edits it anymore.
enum MenuBarStyle: String, Codable, CaseIterable, Identifiable {
    case classic  // SF system, short labels + space separators, weights vary
    case mono     // SF Mono, labels inline with `:` (e.g. 5h:26), tight
    case badge    // each metric in a rounded tinted pill with matching text

    var id: String { rawValue }
}

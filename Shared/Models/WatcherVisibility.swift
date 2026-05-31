import Foundation

/// How long a session stays visible in the watcher overlay after Claude stops
/// writing to its JSONL. Longer windows keep more (cold) project directories in
/// the per-tick scan, so they cost more local CPU. Capped at 7 days on purpose
/// (no "always") to keep the steady-state scan bounded.
enum WatcherVisibility: Int, CaseIterable, Sendable {
    case thirtyMinutes = 1800
    case twoHours = 7200
    case eightHours = 28800
    case oneDay = 86400
    case sevenDays = 604800

    var seconds: TimeInterval { TimeInterval(rawValue) }

    /// Compact, locale-neutral chip label.
    var label: String {
        switch self {
        case .thirtyMinutes: return "30m"
        case .twoHours: return "2h"
        case .eightHours: return "8h"
        case .oneDay: return "1d"
        case .sevenDays: return "7d"
        }
    }
}

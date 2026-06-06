import Foundation

enum PacingZone: String {
    case chill    // safely below the ideal pace
    case onTrack  // within ±margin of the ideal pace
    case warning  // running ahead by more than the margin but below the hot threshold
    case hot      // running ahead by more than 2x the margin
}

enum PacingBucket: String, CaseIterable {
    case fiveHour
    case sevenDay
    case sonnet

    var periodDuration: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 3600
        case .sevenDay, .sonnet: return 7 * 24 * 3600
        }
    }

    var metricID: MetricID {
        switch self {
        case .fiveHour: return .fiveHour
        case .sevenDay: return .sevenDay
        case .sonnet: return .sonnet
        }
    }
}

struct PacingResult {
    let delta: Double
    let expectedUsage: Double
    let actualUsage: Double
    let zone: PacingZone
    let message: String
    let resetDate: Date?
}

/// Workweek pacing configuration. When `enabled`, the pacing "expected" line
/// only advances over the user's active days (Gregorian weekday numbers, 1=Sun
/// ... 7=Sat), so off-days (weekends by default) don't push the expected pace
/// forward - a Mon-Fri user no longer looks "hot" just because the calendar
/// week elapsed while they rested. Disabled = every day counts (classic rolling
/// window). Applies to the weekly + Sonnet buckets only; the 5h session is an
/// intraday window and is never schedule-adjusted.
struct PacingSchedule: Equatable, Sendable {
    var enabled: Bool
    /// Gregorian weekday numbers considered active (1=Sunday ... 7=Saturday).
    var activeDays: Set<Int>

    static let allDays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    /// Monday through Friday - the default selection when the user enables it.
    static let workweek: Set<Int> = [2, 3, 4, 5, 6]
    /// Classic behaviour: feature off, every day counts.
    static let rolling = PacingSchedule(enabled: false, activeDays: workweek)

    /// Days the calculator actually uses. Falls back to all seven days when the
    /// feature is off or the selection is empty - the empty-set guard keeps the
    /// active-seconds denominator from ever hitting zero.
    var effectiveActiveDays: Set<Int> {
        guard enabled, !activeDays.isEmpty else { return Self.allDays }
        return activeDays
    }

    /// True only when the schedule meaningfully excludes at least one day.
    /// Drives the workweek badge on pacing surfaces.
    var isActive: Bool {
        enabled && !activeDays.isEmpty && activeDays.count < 7
    }

    /// Whether `date` falls on an excluded (off) day. False unless the schedule
    /// is active. Drives the "resting" badge variant on off-days.
    func isOffDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isActive else { return false }
        return !effectiveActiveDays.contains(calendar.component(.weekday, from: date))
    }
}

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
    /// When true, the active days are further narrowed to `[startHour, endHour)`
    /// in local time - the off-hours of an active day don't advance the pace
    /// either. Same hours apply to every active day (no per-day schedules).
    var hoursEnabled: Bool = false
    var startHour: Int = 9
    var endHour: Int = 18

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

    /// Active-hours window `(start, end)` in 24h local time, or nil for full
    /// days. nil whenever the feature is off, hours are off, or the range is
    /// degenerate (so the calculator never divides by an empty window).
    var effectiveHours: (start: Int, end: Int)? {
        guard enabled, hoursEnabled, endHour > startHour else { return nil }
        return (startHour, endHour)
    }

    /// True when the schedule meaningfully restricts time - at least one day
    /// excluded OR the hours narrowed. Drives the workweek badge + off hatch.
    var isActive: Bool {
        guard enabled, !activeDays.isEmpty else { return false }
        return activeDays.count < 7 || effectiveHours != nil
    }

    /// Whether `date` is outside the active time - an excluded day, or an off
    /// hour of an active day. False unless active. Drives the "resting" badge
    /// variant + the muted pace marker.
    func isOffDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isActive else { return false }
        if !effectiveActiveDays.contains(calendar.component(.weekday, from: date)) { return true }
        if let h = effectiveHours {
            let hour = calendar.component(.hour, from: date)
            if hour < h.start || hour >= h.end { return true }
        }
        return false
    }

    /// Off-time spans within the window `[resetDate - period, resetDate]`, as
    /// x-fractions (0...1), computed as the complement of the active intervals so
    /// it honors both excluded days and off-hours. Empty unless active.
    func offDayRanges(resetDate: Date, period: TimeInterval = 7 * 24 * 3600, calendar: Calendar = .current) -> [ClosedRange<Double>] {
        guard isActive else { return [] }
        let windowStart = resetDate.addingTimeInterval(-period)
        let active = PacingCalculator.activeIntervals(
            from: windowStart, to: resetDate,
            activeDays: effectiveActiveDays, hours: effectiveHours, calendar: calendar
        )
        func frac(_ d: Date) -> Double { min(max(d.timeIntervalSince(windowStart) / period, 0), 1) }
        var ranges: [ClosedRange<Double>] = []
        var prevEnd = windowStart
        for iv in active {
            if iv.start > prevEnd {
                let lo = frac(prevEnd), hi = frac(iv.start)
                if hi > lo { ranges.append(lo...hi) }
            }
            if iv.end > prevEnd { prevEnd = iv.end }
        }
        if prevEnd < resetDate {
            let lo = frac(prevEnd), hi = frac(resetDate)
            if hi > lo { ranges.append(lo...hi) }
        }
        return ranges
    }
}

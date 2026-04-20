import Foundation

/// Centralises the reset countdown formatting shared across the menu bar,
/// the popover and the dashboard. Produces both a relative string
/// ("1h25" / "25min" / "3d 14h") and an absolute one ("20:30" / "Thu 19:00"
/// / "Apr 24 19:00") for a given reset Date.
///
/// The 5h and 7d buckets share the same formatter but use different thresholds:
/// - 5h resets are always within ~5 hours, so relative is always "XhYY" or "YYmin"
/// - 7d resets can be up to 7 days out, so relative uses "XdYh" / "XhYm"
enum ResetCountdownFormatter {
    /// Session bucket (5h). Returns empty strings when `date` is nil.
    /// Relative: "1h25", "25min", localized "now"
    /// Absolute: "20:30" if same calendar day as `now`, "Fri 08:00" otherwise
    static func session(from date: Date?, now: Date = Date()) -> (relative: String, absolute: String) {
        guard let date else { return ("", "") }
        let diff = date.timeIntervalSince(now)
        let relative: String
        if diff > 0 {
            let h = Int(diff) / 3600
            let m = (Int(diff) % 3600) / 60
            // Clock-style format: "1h25" when hours are present, "25min" otherwise.
            // The 2-digit padding keeps the width stable as minutes drain.
            relative = h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m)min"
        } else {
            relative = String(localized: "relative.now")
        }
        let absolute = formatAbsolute(date, now: now, mode: .session)
        return (relative, absolute)
    }

    /// Weekly bucket (7d). Returns empty strings when `date` is nil.
    /// Relative: "3d 14h", "14h 05", "25min", localized "now"
    /// Absolute: "Thu 19:00" within the next 6 days, "Apr 24 19:00" beyond
    static func weekly(from date: Date?, now: Date = Date()) -> (relative: String, absolute: String) {
        guard let date else { return ("", "") }
        let diff = date.timeIntervalSince(now)
        let relative: String
        if diff > 0 {
            let totalSeconds = Int(diff)
            let days = totalSeconds / 86_400
            let hours = (totalSeconds % 86_400) / 3600
            let minutes = (totalSeconds % 3600) / 60
            if days > 0 {
                // "3d 14h" - minutes omitted at that scale, too noisy
                relative = "\(days)d \(hours)h"
            } else if hours > 0 {
                // "14h 05" - keep minutes readable in the last day
                relative = "\(hours)h \(String(format: "%02d", minutes))"
            } else {
                relative = "\(minutes)min"
            }
        } else {
            relative = String(localized: "relative.now")
        }
        let absolute = formatAbsolute(date, now: now, mode: .weekly)
        return (relative, absolute)
    }

    /// Combines relative and absolute into a single string according to
    /// the user's `ResetDisplayFormat` preference.
    static func display(
        relative: String,
        absolute: String,
        format: ResetDisplayFormat
    ) -> String {
        switch format {
        case .relative: return relative
        case .absolute: return absolute
        case .both:
            if relative.isEmpty { return absolute }
            if absolute.isEmpty { return relative }
            return "\(relative) - \(absolute)"
        }
    }

    // MARK: - Absolute formatting

    private enum AbsoluteMode { case session, weekly }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let weekdayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        // Use the user's locale for "Thu" / "Jeu." etc.
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        return f
    }()

    private static let monthDayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMM d HH:mm")
        return f
    }()

    private static func formatAbsolute(_ date: Date, now: Date, mode: AbsoluteMode) -> String {
        let calendar = Calendar.current
        let sameDay = calendar.isDate(date, inSameDayAs: now)
        if sameDay { return timeFormatter.string(from: date) }

        switch mode {
        case .session:
            // Session resets never cross a week boundary, so weekday + time is
            // always enough.
            return weekdayTimeFormatter.string(from: date)
        case .weekly:
            // Weekly resets can be up to 7 days out. Use weekday for 1-6 days,
            // month+day for the edge "1 week from now" case.
            guard let days = calendar.dateComponents([.day], from: now, to: date).day else {
                return weekdayTimeFormatter.string(from: date)
            }
            return days <= 6
                ? weekdayTimeFormatter.string(from: date)
                : monthDayTimeFormatter.string(from: date)
        }
    }
}

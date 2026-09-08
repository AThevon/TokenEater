import Foundation

/// Computes the X-axis date domain the History chart should always span, even
/// when only one bucket has data. Pinning the scale stops SwiftUI Charts from
/// stretching a single bar across the full width. Pure with injectable `now` /
/// `calendar` (like `PacingCalculator`) so the boundary rounding is testable.
///
/// Both edges round to the bucket boundary that fully contains the edge bar:
/// - end  -> next hour / next day so today's bar (anchored at the start of the
///   period) doesn't clip on the right,
/// - start -> six calendar days ago for 7d, matching the History widget; other
///   ranges round the rolling start down to its bucket boundary.
enum ChartDomainCalculator {
    static func domain(
        range: HistoryRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let rawStart = now.addingTimeInterval(-range.seconds)
        if range.isHourly {
            let endComps = calendar.dateComponents([.year, .month, .day, .hour], from: now)
            let endOfHour = calendar.date(from: endComps) ?? now
            let end = calendar.date(byAdding: .hour, value: 1, to: endOfHour) ?? now
            let startComps = calendar.dateComponents([.year, .month, .day, .hour], from: rawStart)
            let start = calendar.date(from: startComps) ?? rawStart
            return (start: start, end: end)
        } else {
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            let start = range == .sevenDays
                ? calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? rawStart
                : calendar.startOfDay(for: rawStart)
            return (start: start, end: end)
        }
    }
}

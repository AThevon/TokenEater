import Testing
import Foundation

@Suite("MonitoringInsightsStore.dailyTotalsByDay")
struct MonitoringInsightsStoreTests {

    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static func bucket(_ date: Date, total: Int) -> HistoryBucket {
        HistoryBucket(
            date: date,
            tokensByModel: [.sonnet: total],
            tokensByProject: [:],
            sessionsCount: 1,
            inputTokens: 0,
            outputTokens: 0,
            cacheReadTokens: 0,
            cacheCreateTokens: 0
        )
    }

    /// Reproduces issue #179: Mon-Fri have data, Sat & Sun are empty, today is
    /// Sunday. The result must keep each day's value in its own calendar slot,
    /// with explicit zeros for the empty days - not a compacted 5-element array
    /// that shifts Thu/Fri onto the wrong weekday.
    @Test("zero-fills empty days into the correct calendar slots")
    func zeroFillsEmptyDays() {
        let cal = Self.utcCalendar
        let buckets = [
            Self.bucket(Self.day(2026, 5, 25), total: 100), // Mon
            Self.bucket(Self.day(2026, 5, 26), total: 200), // Tue
            Self.bucket(Self.day(2026, 5, 27), total: 300), // Wed
            Self.bucket(Self.day(2026, 5, 28), total: 400), // Thu
            Self.bucket(Self.day(2026, 5, 29), total: 500)  // Fri
            // Sat 05-30 and Sun 05-31 have no activity
        ]
        let today = Self.day(2026, 5, 31) // Sunday

        let totals = MonitoringInsightsStore.dailyTotalsByDay(
            from: buckets, days: 7, today: today, calendar: cal
        )

        #expect(totals == [100, 200, 300, 400, 500, 0, 0])
    }

    /// A single mid-week day of activity lands on the right slot, today last.
    @Test("places a lone active day in the right slot")
    func loneActiveDay() {
        let cal = Self.utcCalendar
        let buckets = [Self.bucket(Self.day(2026, 5, 28), total: 999)] // Thu
        let today = Self.day(2026, 5, 31) // Sun

        let totals = MonitoringInsightsStore.dailyTotalsByDay(
            from: buckets, days: 7, today: today, calendar: cal
        )

        // Mon..Sun -> only Thu (index 3) is non-zero.
        #expect(totals == [0, 0, 0, 999, 0, 0, 0])
    }

    /// No history at all keeps the widget's empty state.
    @Test("returns empty array when there are no buckets")
    func emptyWhenNoBuckets() {
        let totals = MonitoringInsightsStore.dailyTotalsByDay(
            from: [], days: 7, today: Self.day(2026, 5, 31), calendar: Self.utcCalendar
        )
        #expect(totals.isEmpty)
    }

    /// Out-of-order or duplicate-day buckets still align by date.
    @Test("sorts and merges by calendar day regardless of input order")
    func unorderedInput() {
        let cal = Self.utcCalendar
        let buckets = [
            Self.bucket(Self.day(2026, 5, 31), total: 50), // Sun (today)
            Self.bucket(Self.day(2026, 5, 25), total: 100) // Mon
        ]
        let today = Self.day(2026, 5, 31)

        let totals = MonitoringInsightsStore.dailyTotalsByDay(
            from: buckets, days: 7, today: today, calendar: cal
        )

        #expect(totals == [100, 0, 0, 0, 0, 0, 50])
    }
}

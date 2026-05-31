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

    /// loadHistory's rolling window can surface a partial 8th day. It must be
    /// trimmed so the in-app weekly total matches the 7 calendar days the
    /// widget renders (#179 review finding).
    @Test("drops buckets older than the 7-day calendar window")
    func dropsOutOfWindowBuckets() {
        let cal = Self.utcCalendar
        let buckets = [
            Self.bucket(Self.day(2026, 5, 24), total: 777), // today-7, partial 8th day
            Self.bucket(Self.day(2026, 5, 25), total: 100), // today-6, oldest in window
            Self.bucket(Self.day(2026, 5, 31), total: 200)  // today
        ]
        let today = Self.day(2026, 5, 31)

        let windowed = MonitoringInsightsStore.bucketsInWindow(
            buckets, days: 7, today: today, calendar: cal
        )

        #expect(windowed.map { $0.totalActive } == [100, 200])
    }

    /// The in-app total (sum of windowed buckets) and the widget total (sum of
    /// the densified slots) must agree, even when the raw input spans 8 days.
    @Test("windowed sum equals densified widget sum")
    func windowedSumMatchesWidgetSum() {
        let cal = Self.utcCalendar
        let buckets = [
            Self.bucket(Self.day(2026, 5, 24), total: 777), // out of window
            Self.bucket(Self.day(2026, 5, 26), total: 100),
            Self.bucket(Self.day(2026, 5, 29), total: 250),
            Self.bucket(Self.day(2026, 5, 31), total: 60)
        ]
        let today = Self.day(2026, 5, 31)

        let inApp = MonitoringInsightsStore.bucketsInWindow(buckets, days: 7, today: today, calendar: cal)
            .map { $0.totalActive }.reduce(0, +)
        let widget = MonitoringInsightsStore.dailyTotalsByDay(from: buckets, days: 7, today: today, calendar: cal)
            .reduce(0, +)

        #expect(inApp == widget)
        #expect(inApp == 410)
    }

    /// When the only activity is on the dropped 8th day, the widget array must
    /// be empty so it shows the dedicated empty state rather than a flat-0 chart.
    @Test("returns empty array when every slot is zero")
    func emptyWhenAllSlotsZero() {
        let cal = Self.utcCalendar
        let buckets = [Self.bucket(Self.day(2026, 5, 24), total: 777)] // today-7 only
        let today = Self.day(2026, 5, 31)

        let totals = MonitoringInsightsStore.dailyTotalsByDay(
            from: buckets, days: 7, today: today, calendar: cal
        )

        #expect(totals.isEmpty)
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

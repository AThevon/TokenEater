import Testing
import Foundation

@Suite("ChartDomainCalculator")
struct ChartDomainCalculatorTests {

    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private static func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        utcCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test("daily range rounds start and end to day boundaries")
    func dailyRangeBoundaries() {
        let cal = Self.utcCalendar
        let now = Self.at(2026, 5, 31, 14, 37) // Sunday afternoon
        let domain = ChartDomainCalculator.domain(range: .sevenDays, now: now, calendar: cal)
        // end = start of 06-01 (tomorrow)
        #expect(domain.end == Self.at(2026, 6, 1, 0, 0))
        // Seven calendar days including today match the History widget.
        #expect(domain.start == Self.at(2026, 5, 25, 0, 0))
    }

    /// Hourly range (24h): both edges round to the hour boundary, end is next hour.
    @Test("hourly range rounds start and end to hour boundaries")
    func hourlyRangeBoundaries() {
        let cal = Self.utcCalendar
        let now = Self.at(2026, 5, 31, 14, 37)
        let domain = ChartDomainCalculator.domain(range: .twentyFourHours, now: now, calendar: cal)
        // end = start of next hour after 14:xx -> 15:00
        #expect(domain.end == Self.at(2026, 5, 31, 15, 0))
        // rawStart = now - 24h = 05-30 14:37 -> start of that hour 14:00
        #expect(domain.start == Self.at(2026, 5, 30, 14, 0))
    }

    @Test("Seven-day domain stays calendar-aligned across daylight saving time")
    func weeklyDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 18))!
        let domain = ChartDomainCalculator.domain(range: .sevenDays, now: now, calendar: calendar)
        #expect(calendar.dateComponents([.day], from: domain.start, to: domain.end).day == 7)
        #expect(calendar.component(.hour, from: domain.start) == 0)
        #expect(calendar.component(.day, from: domain.start) == 4)
    }

    @Test("end is always strictly after start")
    func endAfterStart() {
        let cal = Self.utcCalendar
        let now = Self.at(2026, 5, 31, 0, 5)
        for range in HistoryRange.allCases {
            let d = ChartDomainCalculator.domain(range: range, now: now, calendar: cal)
            #expect(d.end > d.start)
        }
    }
}

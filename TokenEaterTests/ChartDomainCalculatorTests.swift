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

    /// Daily range: end snaps to the start of tomorrow, start snaps to the
    /// start of the day containing (now - range.seconds), so edge bars never clip.
    @Test("daily range rounds start and end to day boundaries")
    func dailyRangeBoundaries() {
        let cal = Self.utcCalendar
        let now = Self.at(2026, 5, 31, 14, 37) // Sunday afternoon
        let domain = ChartDomainCalculator.domain(range: .sevenDays, now: now, calendar: cal)
        // end = start of 06-01 (tomorrow)
        #expect(domain.end == Self.at(2026, 6, 1, 0, 0))
        // rawStart = now - 7d = 05-24 14:37 -> start of day 05-24
        #expect(domain.start == Self.at(2026, 5, 24, 0, 0))
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

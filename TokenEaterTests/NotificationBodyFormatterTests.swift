import Testing
import Foundation

@Suite("NotificationBodyFormatter")
struct NotificationBodyFormatterTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - formatCountdown

    @Test("formatCountdown shows minutes only when < 1h")
    func countdownMinutesOnly() {
        let target = now.addingTimeInterval(45 * 60)
        let result = NotificationBodyFormatter.formatCountdown(from: now, to: target)
        #expect(result == "45min")
    }

    @Test("formatCountdown shows 0min for very short interval")
    func countdownVeryShort() {
        let target = now.addingTimeInterval(20)
        let result = NotificationBodyFormatter.formatCountdown(from: now, to: target)
        #expect(result == "0min")
    }

    @Test("formatCountdown shows hours and minutes")
    func countdownHoursAndMinutes() {
        let target = now.addingTimeInterval(2 * 3600 + 34 * 60)
        let result = NotificationBodyFormatter.formatCountdown(from: now, to: target)
        #expect(result == "2h 34min")
    }

    @Test("formatCountdown shows exact hours")
    func countdownExactHours() {
        let target = now.addingTimeInterval(3 * 3600)
        let result = NotificationBodyFormatter.formatCountdown(from: now, to: target)
        #expect(result == "3h 0min")
    }

    @Test("formatCountdown returns non-empty for >= 24h")
    func countdownDays() {
        let target = now.addingTimeInterval(3 * 24 * 3600 + 5 * 3600)
        let result = NotificationBodyFormatter.formatCountdown(from: now, to: target)
        #expect(!result.isEmpty)
    }

    @Test("formatCountdown returns non-empty for past date")
    func countdownPastDate() {
        let target = now.addingTimeInterval(-60)
        let result = NotificationBodyFormatter.formatCountdown(from: now, to: target)
        #expect(!result.isEmpty)
    }

    // MARK: - formatTime

    @Test("formatTime returns non-empty string")
    func formatTimeNonEmpty() {
        let result = NotificationBodyFormatter.formatTime(now)
        #expect(!result.isEmpty)
    }

    @Test("formatTime returns consistent results for same date")
    func formatTimeConsistent() {
        let a = NotificationBodyFormatter.formatTime(now)
        let b = NotificationBodyFormatter.formatTime(now)
        #expect(a == b)
    }

    // MARK: - formatDateTime

    @Test("formatDateTime returns non-empty string")
    func formatDateTimeNonEmpty() {
        let result = NotificationBodyFormatter.formatDateTime(now)
        #expect(!result.isEmpty)
    }

    @Test("formatDateTime includes day information for different dates")
    func formatDateTimeDifferentDates() {
        let date1 = now
        let date2 = now.addingTimeInterval(3 * 24 * 3600)
        let result1 = NotificationBodyFormatter.formatDateTime(date1)
        let result2 = NotificationBodyFormatter.formatDateTime(date2)
        #expect(result1 != result2)
    }
}

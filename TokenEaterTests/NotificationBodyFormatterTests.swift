import Testing
import Foundation

@Suite("NotificationBodyFormatter")
struct NotificationBodyFormatterTests {

    // MARK: - Helpers

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
        let target = now.addingTimeInterval(20) // 20 seconds
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

    // MARK: - Escalation body — routing

    @Test("escalation returns non-empty for all valid levels")
    func escalationNonEmpty() {
        for level: UsageLevel in [.orange, .red] {
            let body = NotificationBodyFormatter.escalationBody(
                metricType: .session, level: level,
                resetsAt: now.addingTimeInterval(3600),
                pacingZone: .onTrack, thresholds: .default, now: now
            )
            #expect(!body.isEmpty, "Body should not be empty for level \(level)")
        }
    }

    @Test("escalation green returns empty")
    func escalationGreenEmpty() {
        let body = NotificationBodyFormatter.escalationBody(
            metricType: .session, level: .green,
            resetsAt: now.addingTimeInterval(3600),
            pacingZone: .onTrack, thresholds: .default, now: now
        )
        #expect(body.isEmpty)
    }

    @Test("escalation with nil resetsAt returns fallback")
    func escalationNilFallback() {
        let withReset = NotificationBodyFormatter.escalationBody(
            metricType: .session, level: .orange,
            resetsAt: now.addingTimeInterval(3600),
            pacingZone: .onTrack, thresholds: .default, now: now
        )
        let withoutReset = NotificationBodyFormatter.escalationBody(
            metricType: .session, level: .orange,
            resetsAt: nil,
            pacingZone: .onTrack, thresholds: .default, now: now
        )
        // Different path → different output (key vs. formatted string)
        #expect(withReset != withoutReset)
    }

    @Test("escalation with past resetsAt returns fallback")
    func escalationPastFallback() {
        let withFuture = NotificationBodyFormatter.escalationBody(
            metricType: .session, level: .orange,
            resetsAt: now.addingTimeInterval(3600),
            pacingZone: .onTrack, thresholds: .default, now: now
        )
        let withPast = NotificationBodyFormatter.escalationBody(
            metricType: .session, level: .orange,
            resetsAt: now.addingTimeInterval(-3600),
            pacingZone: .onTrack, thresholds: .default, now: now
        )
        #expect(withFuture != withPast)
    }

    @Test("escalation session uses different keys per pacing zone")
    func escalationPacingDifferentiation() {
        let reset = now.addingTimeInterval(2 * 3600)
        let chill = NotificationBodyFormatter.escalationBody(
            metricType: .session, level: .orange,
            resetsAt: reset, pacingZone: .chill,
            thresholds: .default, now: now
        )
        let hot = NotificationBodyFormatter.escalationBody(
            metricType: .session, level: .orange,
            resetsAt: reset, pacingZone: .hot,
            thresholds: .default, now: now
        )
        #expect(chill != hot)
    }

    @Test("escalation session vs weekly uses different paths")
    func escalationSessionVsWeekly() {
        let reset = now.addingTimeInterval(2 * 3600)
        let session = NotificationBodyFormatter.escalationBody(
            metricType: .session, level: .orange,
            resetsAt: reset, pacingZone: .onTrack,
            thresholds: .default, now: now
        )
        let weekly = NotificationBodyFormatter.escalationBody(
            metricType: .weekly, level: .orange,
            resetsAt: reset, pacingZone: nil,
            thresholds: .default, now: now
        )
        #expect(session != weekly)
    }

    @Test("red escalation session vs weekly uses different paths")
    func redEscalationSessionVsWeekly() {
        let reset = now.addingTimeInterval(2 * 3600)
        let session = NotificationBodyFormatter.escalationBody(
            metricType: .session, level: .red,
            resetsAt: reset, pacingZone: nil,
            thresholds: .default, now: now
        )
        let weekly = NotificationBodyFormatter.escalationBody(
            metricType: .weekly, level: .red,
            resetsAt: reset, pacingZone: nil,
            thresholds: .default, now: now
        )
        #expect(session != weekly)
    }

    // MARK: - Recovery body — routing

    @Test("recovery returns non-empty for all metric types")
    func recoveryNonEmpty() {
        for type: NotificationBodyFormatter.MetricType in [.session, .weekly] {
            let body = NotificationBodyFormatter.recoveryBody(
                metricType: type,
                resetsAt: now.addingTimeInterval(5 * 3600),
                now: now
            )
            #expect(!body.isEmpty, "Body should not be empty for \(type)")
        }
    }

    @Test("recovery with nil resetsAt returns fallback")
    func recoveryNilFallback() {
        let withReset = NotificationBodyFormatter.recoveryBody(
            metricType: .session,
            resetsAt: now.addingTimeInterval(5 * 3600),
            now: now
        )
        let withoutReset = NotificationBodyFormatter.recoveryBody(
            metricType: .session,
            resetsAt: nil,
            now: now
        )
        #expect(withReset != withoutReset)
    }

    @Test("recovery with past resetsAt returns fallback")
    func recoveryPastFallback() {
        let withFuture = NotificationBodyFormatter.recoveryBody(
            metricType: .session,
            resetsAt: now.addingTimeInterval(5 * 3600),
            now: now
        )
        let withPast = NotificationBodyFormatter.recoveryBody(
            metricType: .session,
            resetsAt: now.addingTimeInterval(-60),
            now: now
        )
        #expect(withFuture != withPast)
    }

    @Test("recovery session vs weekly uses different paths")
    func recoverySessionVsWeekly() {
        let reset = now.addingTimeInterval(5 * 3600)
        let session = NotificationBodyFormatter.recoveryBody(
            metricType: .session, resetsAt: reset, now: now
        )
        let weekly = NotificationBodyFormatter.recoveryBody(
            metricType: .weekly, resetsAt: reset, now: now
        )
        #expect(session != weekly)
    }
}

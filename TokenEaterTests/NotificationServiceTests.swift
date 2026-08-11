import Testing
import Foundation
import UserNotifications

@Suite("NotificationService")
struct NotificationServiceTests {

    private func makeSUT() -> (NotificationService, MockNotificationCenter, MockNotificationStateStore) {
        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        let service = NotificationService(center: center, stateStore: state)
        return (service, center, state)
    }

    private func toggles(sendRecovery: Bool = true) -> NotificationToggles {
        NotificationToggles(
            masterEnabled: true,
            trackFiveHour: true, trackWeekly: true, trackSonnet: false, trackFable: false,
            sendRecovery: sendRecovery, pacingHot: false, pacingWarning: false,
            resetReminderSession: false, resetReminderWeekly: false,
            resetReminderSessionOffsetMinutes: 15, resetReminderWeeklyOffsetMinutes: 60,
            extraCredits: false, tokenExpired: true,
            smartColorEnabled: false, smartColorProfile: .default,
            pacingMargin: 10, thresholds: .default,
            vendorDegraded: false, vendorRestored: false
        )
    }

    private func snap(_ pct: Int) -> MetricSnapshot {
        MetricSnapshot(pct: pct, resetsAt: Date().addingTimeInterval(3600), windowDuration: 5 * 3600)
    }

    @Test("escalation from orange to red fires once and records the new level")
    func escalationFiresOnEntry() {
        let (service, center, state) = makeSUT()
        state.levels["lastLevel_fiveHour"] = UsageLevel.orange.rawValue

        service.evaluate(
            fiveHour: snap(96), sevenDay: snap(0), sonnet: snap(0), fable: snap(0),
            sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles()
        )

        #expect(center.addedIDs.contains("escalation_fiveHour"))
        #expect(state.levels["lastLevel_fiveHour"] == UsageLevel.red.rawValue)
    }

    @Test("staying at the same level does not re-fire")
    func sameLevelDoesNotRefire() {
        let (service, center, state) = makeSUT()
        state.levels["lastLevel_fiveHour"] = UsageLevel.red.rawValue

        service.evaluate(
            fiveHour: snap(96), sevenDay: snap(0), sonnet: snap(0), fable: snap(0),
            sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles()
        )

        #expect(!center.addedIDs.contains("escalation_fiveHour"))
    }

    @Test("recovery to green fires on a real window reset")
    func recoveryFiresWhenEnabled() {
        let (service, center, state) = makeSUT()
        state.levels["lastLevel_fiveHour"] = UsageLevel.red.rawValue
        // A real reset: the last-seen boundary is well in the past and the new
        // snapshot's resets_at has jumped forward (#244 gate).
        state.resetsAts["lastResetsAt_fiveHour"] = Date().addingTimeInterval(-10 * 3600)

        service.evaluate(
            fiveHour: snap(10), sevenDay: snap(0), sonnet: snap(0), fable: snap(0),
            sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles(sendRecovery: true)
        )

        #expect(center.addedIDs.contains("recovery_fiveHour"))
        #expect(state.levels["lastLevel_fiveHour"] == UsageLevel.green.rawValue)
    }

    @Test("recovery does NOT fire on a mid-window level dip without a real reset (#244)")
    func recoveryDoesNotFireMidWindow() {
        let (service, center, state) = makeSUT()
        state.levels["lastLevel_weekly"] = UsageLevel.red.rawValue
        // Same window: the last-seen reset boundary equals the snapshot's
        // resets_at (nothing rolled). A red->green dip must stay silent, or the
        // user gets a false "weekly reset" notification mid-week.
        let weekly = MetricSnapshot(pct: 10, resetsAt: Date().addingTimeInterval(2 * 24 * 3600), windowDuration: 7 * 86_400)
        state.resetsAts["lastResetsAt_weekly"] = weekly.resetsAt

        service.evaluate(
            fiveHour: snap(0), sevenDay: weekly, sonnet: snap(0), fable: snap(0),
            sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles(sendRecovery: true)
        )

        #expect(!center.addedIDs.contains("recovery_weekly"))
        // The level is still advanced (dedup), only the notification is suppressed.
        #expect(state.levels["lastLevel_weekly"] == UsageLevel.green.rawValue)
    }

    @Test("recovery stays silent when sendRecovery is off")
    func recoverySilentWhenDisabled() {
        let (service, center, state) = makeSUT()
        state.levels["lastLevel_fiveHour"] = UsageLevel.red.rawValue

        service.evaluate(
            fiveHour: snap(10), sevenDay: snap(0), sonnet: snap(0), fable: snap(0),
            sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles(sendRecovery: false)
        )

        #expect(!center.addedIDs.contains("recovery_fiveHour"))
    }

    @Test("token expired de-dupes within one hour")
    func tokenExpiredDedupes() {
        let (service, center, state) = makeSUT()
        _ = state

        service.notifyTokenExpired(toggle: true)
        #expect(center.addedIDs.filter { $0 == "token_expired" }.count == 1)

        service.notifyTokenExpired(toggle: true)
        #expect(center.addedIDs.filter { $0 == "token_expired" }.count == 1)
    }
}

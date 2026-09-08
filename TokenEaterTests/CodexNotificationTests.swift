import Testing
import Foundation
import UserNotifications

@Suite("Codex notifications")
struct CodexNotificationTests {

    // MARK: - Helpers

    private func makeSUT() -> (NotificationService, MockNotificationCenter, MockNotificationStateStore) {
        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        return (NotificationService(center: center, stateStore: state), center, state)
    }

    private func toggles(
        masterEnabled: Bool = true,
        codex: CodexNotificationToggles = .default,
        sessionOffset: Int = 15,
        weeklyOffset: Int = 60
    ) -> NotificationToggles {
        NotificationToggles(
            masterEnabled: masterEnabled,
            trackFiveHour: false, trackWeekly: false, trackSonnet: false, trackFable: false,
            sendRecovery: true, pacingHot: true, pacingWarning: true,
            resetReminderSession: false, resetReminderWeekly: false,
            resetReminderSessionOffsetMinutes: sessionOffset, resetReminderWeeklyOffsetMinutes: weeklyOffset,
            extraCredits: false, tokenExpired: false,
            smartColorEnabled: false, smartColorProfile: .default,
            pacingMargin: 10, thresholds: .default,
            vendorDegraded: false, vendorRestored: false,
            codex: codex
        )
    }

    private func window(
        kind: CodexWindowKind,
        pct: Int,
        resetIn: TimeInterval = 3_600,
        isIdle: Bool = false,
        pacing: PacingResult? = nil
    ) -> CodexWindowSnapshot {
        let duration: TimeInterval = kind == .session ? 18_000 : 604_800
        return CodexWindowSnapshot(
            kind: kind,
            pct: pct,
            utilization: Double(pct),
            resetDate: Date().addingTimeInterval(resetIn),
            windowDuration: duration,
            isIdle: isIdle,
            relativeReset: "1h00",
            absoluteReset: "20:30",
            pacing: pacing
        )
    }

    // MARK: - Gating

    @Test("the global master switch silences Codex and drops its reminders")
    func masterSwitchWins() {
        let (service, center, _) = makeSUT()

        service.evaluateCodex(windows: [window(kind: .weekly, pct: 96)], toggles: toggles(masterEnabled: false))

        #expect(center.addedIDs.isEmpty)
        #expect(center.removedIDs.contains("reminder_codex_weekly"))
    }

    @Test("the Codex sub-switch silences Codex without touching Claude alerts")
    func codexSubSwitch() {
        let (service, center, _) = makeSUT()
        var codex = CodexNotificationToggles.default
        codex.enabled = false

        service.evaluateCodex(windows: [window(kind: .weekly, pct: 96)], toggles: toggles(codex: codex))

        #expect(center.addedIDs.isEmpty)
    }

    @Test("per-window tracking toggles are honoured")
    func perWindowToggles() {
        let (service, center, state) = makeSUT()
        var codex = CodexNotificationToggles.default
        codex.trackSession = false
        state.levels["lastLevel_codexSession"] = UsageLevel.green.rawValue
        state.levels["lastLevel_codexWeekly"] = UsageLevel.green.rawValue

        service.evaluateCodex(
            windows: [window(kind: .session, pct: 96), window(kind: .weekly, pct: 96)],
            toggles: toggles(codex: codex)
        )

        #expect(!center.addedIDs.contains("escalation_codexSession"))
        #expect(center.addedIDs.contains("escalation_codexWeekly"))
    }

    // MARK: - Escalation

    @Test("crossing into red fires once per window and records the level")
    func escalation() {
        let (service, center, state) = makeSUT()
        state.levels["lastLevel_codexSession"] = UsageLevel.orange.rawValue

        service.evaluateCodex(windows: [window(kind: .session, pct: 96)], toggles: toggles())

        #expect(center.addedIDs.contains("escalation_codexSession"))
        #expect(state.levels["lastLevel_codexSession"] == UsageLevel.red.rawValue)
    }

    @Test("staying at the same level does not re-fire")
    func noRefire() {
        let (service, center, state) = makeSUT()
        state.levels["lastLevel_codexWeekly"] = UsageLevel.red.rawValue

        service.evaluateCodex(windows: [window(kind: .weekly, pct: 97)], toggles: toggles())

        #expect(!center.addedIDs.contains("escalation_codexWeekly"))
    }

    @Test("dropping back to green does not fire a recovery: the reset alert owns that message")
    func noDuplicateRecovery() {
        let (service, center, state) = makeSUT()
        state.levels["lastLevel_codexWeekly"] = UsageLevel.red.rawValue
        // A real rollover: the previous deadline has passed and usage is back to zero.
        state.resetsAts["lastResetsAt_codexWeekly"] = Date().addingTimeInterval(-604_800)
        state.resetsAts["codexResetAt_codexWeekly"] = Date().addingTimeInterval(-60)
        state.utilizations["codexUtilization_codexWeekly"] = 96

        service.evaluateCodex(windows: [window(kind: .weekly, pct: 0, resetIn: 604_800)], toggles: toggles())

        #expect(!center.addedIDs.contains("recovery_codexWeekly"))
        #expect(center.addedIDs.contains("codex_reset_codexWeekly"))
    }

    // MARK: - Window reset alert

    @Test("a real rollover fires the reset alert exactly once")
    func resetAlertFiresOnce() {
        let (service, center, state) = makeSUT()
        state.resetsAts["codexResetAt_codexWeekly"] = Date().addingTimeInterval(-60)
        state.utilizations["codexUtilization_codexWeekly"] = 88

        let fresh = window(kind: .weekly, pct: 1, resetIn: 604_800)
        service.evaluateCodex(windows: [fresh], toggles: toggles())
        #expect(center.addedIDs.filter { $0 == "codex_reset_codexWeekly" }.count == 1)

        // Next poll inside the same fresh window stays silent.
        service.evaluateCodex(windows: [fresh], toggles: toggles())
        #expect(center.addedIDs.filter { $0 == "codex_reset_codexWeekly" }.count == 1)
    }

    @Test("an unused window whose deadline slides never fires the reset alert")
    func idleWindowStaysSilent() {
        let (service, center, _) = makeSUT()

        // Five polls of an untouched window: reset_at moves forward every time.
        for tick in 0..<5 {
            let sliding = CodexWindowSnapshot(
                kind: .weekly,
                pct: 0,
                utilization: 0,
                resetDate: Date().addingTimeInterval(604_800 + Double(tick) * 300),
                windowDuration: 604_800,
                isIdle: true,
                relativeReset: "6d", absoluteReset: "Mon 09:00",
                pacing: nil
            )
            service.evaluateCodex(windows: [sliding], toggles: toggles())
        }

        #expect(!center.addedIDs.contains("codex_reset_codexWeekly"))
    }

    @Test("the reset alert can be switched off on its own")
    func resetAlertToggle() {
        let (service, center, state) = makeSUT()
        var codex = CodexNotificationToggles.default
        codex.windowReset = false
        state.resetsAts["codexResetAt_codexSession"] = Date().addingTimeInterval(-60)
        state.utilizations["codexUtilization_codexSession"] = 90

        service.evaluateCodex(windows: [window(kind: .session, pct: 0, resetIn: 18_000)], toggles: toggles(codex: codex))

        #expect(!center.addedIDs.contains("codex_reset_codexSession"))
    }

    @Test("the first ever observation does not announce a reset")
    func firstObservationIsSilent() {
        let (service, center, _) = makeSUT()

        service.evaluateCodex(windows: [window(kind: .weekly, pct: 12)], toggles: toggles())

        #expect(!center.addedIDs.contains("codex_reset_codexWeekly"))
    }

    @Test("an unfamiliar window is tracked but never notified about")
    func unknownWindowIsNotNotified() {
        let (service, center, _) = makeSUT()
        let odd = CodexWindowSnapshot(
            kind: .other, pct: 99, utilization: 99,
            resetDate: Date().addingTimeInterval(3_600), windowDuration: 43_200,
            isIdle: false, relativeReset: "1h", absoluteReset: "20:30", pacing: nil
        )

        service.evaluateCodex(windows: [odd], toggles: toggles())

        #expect(center.addedIDs.isEmpty)
    }

    // MARK: - Reminders

    @Test("reminders are scheduled for a window with a real deadline")
    func remindersScheduled() {
        let (service, center, _) = makeSUT()
        var codex = CodexNotificationToggles.default
        codex.resetReminderSession = true
        codex.resetReminderWeekly = true

        service.evaluateCodex(
            windows: [window(kind: .session, pct: 30, resetIn: 3_600), window(kind: .weekly, pct: 30, resetIn: 86_400)],
            toggles: toggles(codex: codex)
        )

        #expect(center.addedIDs.contains("reminder_codex_session"))
        #expect(center.addedIDs.contains("reminder_codex_weekly"))
    }

    @Test("an idle window gets no reminder: its deadline is recomputed on every poll")
    func idleWindowGetsNoReminder() {
        let (service, center, _) = makeSUT()
        var codex = CodexNotificationToggles.default
        codex.resetReminderWeekly = true

        service.evaluateCodex(
            windows: [window(kind: .weekly, pct: 0, resetIn: 604_800, isIdle: true)],
            toggles: toggles(codex: codex)
        )

        #expect(!center.addedIDs.contains("reminder_codex_weekly"))
    }

    @Test("a reminder whose moment already passed is not scheduled")
    func pastReminderIsNotScheduled() {
        let (service, center, _) = makeSUT()
        var codex = CodexNotificationToggles.default
        codex.resetReminderSession = true

        // Resets in 5 minutes, reminder offset is 15: that moment is behind us.
        service.evaluateCodex(
            windows: [window(kind: .session, pct: 30, resetIn: 300)],
            toggles: toggles(codex: codex, sessionOffset: 15)
        )

        #expect(!center.addedIDs.contains("reminder_codex_session"))
    }

    @Test("re-evaluating clears the previous reminders before scheduling new ones")
    func remindersAreReplaced() {
        let (service, center, _) = makeSUT()
        var codex = CodexNotificationToggles.default
        codex.resetReminderWeekly = true

        service.evaluateCodex(windows: [window(kind: .weekly, pct: 30, resetIn: 86_400)], toggles: toggles(codex: codex))

        #expect(center.removedIDs.contains("reminder_codex_weekly"))
    }

    @Test("cancelling drops both Codex reminders and nothing else")
    func cancelReminders() {
        let (service, center, _) = makeSUT()

        service.cancelCodexReminders()

        #expect(center.removedIDs.contains("reminder_codex_session"))
        #expect(center.removedIDs.contains("reminder_codex_weekly"))
        #expect(!center.removedIDs.contains("reminder_weekly"))
    }

    // MARK: - Pacing

    @Test("entering the hot pacing zone fires once")
    func pacingTransition() {
        let (service, center, _) = makeSUT()
        let hot = PacingResult(
            delta: 40, expectedUsage: 20, actualUsage: 60,
            zone: .hot, message: "", resetDate: Date().addingTimeInterval(3_600)
        )

        service.evaluateCodex(windows: [window(kind: .weekly, pct: 60, pacing: hot)], toggles: toggles())

        #expect(center.addedIDs.contains("pacing_hot"))
    }

    // MARK: - Token expiry

    @Test("the login-expired alert fires once per hour at most")
    func tokenExpiredDedupe() {
        let (service, center, _) = makeSUT()

        service.notifyCodexTokenExpired(toggles: toggles())
        service.notifyCodexTokenExpired(toggles: toggles())

        #expect(center.addedIDs.filter { $0 == "codex_token_expired" }.count == 1)
    }

    @Test("the login-expired alert respects both masters and its own toggle")
    func tokenExpiredGating() {
        var codex = CodexNotificationToggles.default
        codex.tokenExpired = false

        let (offService, offCenter, _) = makeSUT()
        offService.notifyCodexTokenExpired(toggles: toggles(codex: codex))
        #expect(offCenter.addedIDs.isEmpty)

        let (masterService, masterCenter, _) = makeSUT()
        masterService.notifyCodexTokenExpired(toggles: toggles(masterEnabled: false))
        #expect(masterCenter.addedIDs.isEmpty)
    }

    // MARK: - Claude is untouched

    @Test("Claude keeps its own behaviour: no window-reset alert is introduced for it")
    func claudeHasNoResetAlert() {
        let (service, center, state) = makeSUT()
        state.levels["lastLevel_weekly"] = UsageLevel.red.rawValue
        state.resetsAts["lastResetsAt_weekly"] = Date().addingTimeInterval(-604_800)

        let claudeToggles = NotificationToggles(
            masterEnabled: true,
            trackFiveHour: true, trackWeekly: true, trackSonnet: false, trackFable: false,
            sendRecovery: true, pacingHot: false, pacingWarning: false,
            resetReminderSession: false, resetReminderWeekly: false,
            resetReminderSessionOffsetMinutes: 15, resetReminderWeeklyOffsetMinutes: 60,
            extraCredits: false, tokenExpired: false,
            smartColorEnabled: false, smartColorProfile: .default,
            pacingMargin: 10, thresholds: .default,
            vendorDegraded: false, vendorRestored: false
        )
        let snapshot = MetricSnapshot(pct: 2, resetsAt: Date().addingTimeInterval(604_800), windowDuration: 604_800)
        service.evaluate(
            fiveHour: MetricSnapshot(pct: 0, resetsAt: nil), sevenDay: snapshot,
            sonnet: MetricSnapshot(pct: 0, resetsAt: nil), fable: MetricSnapshot(pct: 0, resetsAt: nil),
            sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: claudeToggles
        )

        // Claude still uses its existing recovery notification, and gains no
        // Codex-style reset alert.
        #expect(center.addedIDs.contains("recovery_weekly"))
        #expect(!center.addedIDs.contains { $0.hasPrefix("codex_reset_") })
    }
}

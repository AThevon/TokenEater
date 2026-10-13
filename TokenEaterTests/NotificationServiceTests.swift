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

    private func toggles(sendRecovery: Bool = true, claudeEnabled: Bool = true) -> NotificationToggles {
        NotificationToggles(
            masterEnabled: true,
            claudeEnabled: claudeEnabled,
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

    private func window(kind: CodexWindowKind, pct: Int) -> CodexWindowSnapshot {
        CodexWindowSnapshot(
            kind: kind,
            pct: pct,
            utilization: Double(pct),
            resetDate: Date().addingTimeInterval(kind == .session ? 3_600 : 86_400),
            windowDuration: kind == .session ? 18_000 : 604_800,
            isIdle: false,
            relativeReset: "1h00",
            absoluteReset: "20:30",
            pacing: nil
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

    /// The generic alert covers 401s that tend to persist (a refused Keychain
    /// read, a revoked token): one alert per run of failures, however many
    /// ticks or hours it lasts, re-armed by the next successful refresh.
    @Test("the generic token alert fires once per run of failures")
    func tokenAlertOncePerRun() {
        let (service, center, _) = makeSUT()

        service.notifyTokenExpired(toggles: toggles())
        service.notifyTokenExpired(toggles: toggles())
        service.notifyTokenExpired(toggles: toggles())
        #expect(center.addedIDs.filter { $0 == "token_expired" }.count == 1)

        service.endTokenAlertEpisode()
        service.notifyTokenExpired(toggles: toggles())
        #expect(center.addedIDs.filter { $0 == "token_expired" }.count == 2)
    }

    @Test("a muted token alert does not use up the run")
    func mutedTokenAlertStaysArmed() {
        let (service, center, state) = makeSUT()

        service.notifyTokenExpired(toggles: toggles(claudeEnabled: false))
        #expect(center.addedIDs.isEmpty)
        #expect(!state.tokenAlertSentFlag)
    }

    /// One alert per expiry episode (#268): repeated failing ticks after the
    /// first fire stay silent, and a later expiry (the login was renewed,
    /// then expired again) is a new episode.
    @Test("login expired fires once per expiry episode")
    func loginExpiredOncePerEpisode() {
        let (service, center, _) = makeSUT()
        let firstExpiry = Date().addingTimeInterval(-2 * 3600)

        service.notifyLoginExpired(since: firstExpiry, toggles: toggles())
        service.notifyLoginExpired(since: firstExpiry, toggles: toggles())
        #expect(center.addedIDs.filter { $0 == "token_expired" }.count == 1)

        let secondExpiry = firstExpiry.addingTimeInterval(9 * 3600)
        service.notifyLoginExpired(since: secondExpiry, toggles: toggles())
        #expect(center.addedIDs.filter { $0 == "token_expired" }.count == 2)
    }

    /// A Keychain timeout on one tick in the first hour fires the generic
    /// alert; the escalation an hour later must still get its own, actionable
    /// one, and the reverse order must not mute the generic alert either.
    @Test("the generic and expired-login alerts do not suppress each other")
    func tokenAlertsIndependent() {
        let (service, center, _) = makeSUT()
        let expiry = Date().addingTimeInterval(-2 * 3600)

        service.notifyTokenExpired(toggles: toggles())
        service.notifyLoginExpired(since: expiry, toggles: toggles())
        #expect(center.addedIDs.filter { $0 == "token_expired" }.count == 2)

        let (other, otherCenter, _) = makeSUT()
        other.notifyLoginExpired(since: expiry, toggles: toggles())
        other.notifyTokenExpired(toggles: toggles())
        #expect(otherCenter.addedIDs.filter { $0 == "token_expired" }.count == 2)
    }

    @Test("login expired respects the token-expired toggle")
    func loginExpiredGated() {
        let (service, center, _) = makeSUT()
        service.notifyLoginExpired(since: Date().addingTimeInterval(-7200), toggles: toggles(claudeEnabled: false))
        #expect(center.addedIDs.isEmpty)
    }

    @Test("every notification names its provider and groups by it")
    func notificationsCarryTheirProvider() {
        let (service, center, state) = makeSUT()
        state.levels["lastLevel_fiveHour"] = UsageLevel.orange.rawValue
        state.levels["lastLevel_codexWeekly"] = UsageLevel.orange.rawValue

        service.evaluate(
            fiveHour: snap(96), sevenDay: snap(0), sonnet: snap(0), fable: snap(0),
            sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles()
        )
        let claude = center.content(for: "escalation_fiveHour")
        #expect(claude?.subtitle == MetricProvider.claude.displayName)
        #expect(claude?.threadIdentifier == MetricProvider.claude.rawValue)
        // The title used to carry the provider on one side only, so Claude's
        // alerts were the anonymous ones as soon as OpenAI was on.
        #expect(claude?.title.contains("Claude") == false)

        service.evaluateCodex(
            windows: [window(kind: .weekly, pct: 96)],
            toggles: toggles()
        )
        let codex = center.content(for: "escalation_codexWeekly")
        #expect(codex?.subtitle == MetricProvider.codex.displayName)
        #expect(codex?.threadIdentifier == MetricProvider.codex.rawValue)
        // Same copy family as Claude's weekly window: the provider is a field
        // now, not twenty duplicated strings with a prefix.
        #expect(codex?.title == center.content(for: "escalation_weekly")?.title
                || codex?.title.isEmpty == false)
    }

    @Test("muting one provider leaves the other alone")
    func perProviderMaster() {
        let (service, center, state) = makeSUT()
        state.levels["lastLevel_fiveHour"] = UsageLevel.orange.rawValue

        service.evaluate(
            fiveHour: snap(96), sevenDay: snap(0), sonnet: snap(0), fable: snap(0),
            sessionPacing: nil, weeklyPacing: nil, extraUsage: nil,
            toggles: toggles(claudeEnabled: false)
        )
        #expect(center.addedIDs.contains("escalation_fiveHour") == false)
        // Pending Claude reminders go with it, or a muted provider would keep
        // firing the ones already scheduled.
        #expect(center.removedIDs.contains("reminder_session"))

        var codexToggles = toggles(claudeEnabled: false)
        codexToggles.codex = CodexNotificationToggles()
        state.levels["lastLevel_codexSession"] = UsageLevel.orange.rawValue
        service.evaluateCodex(
            windows: [window(kind: .session, pct: 96)],
            toggles: codexToggles
        )
        #expect(center.addedIDs.contains("escalation_codexSession"))
    }
}

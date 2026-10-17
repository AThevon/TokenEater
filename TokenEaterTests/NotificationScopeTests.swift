import Testing
import Foundation
import UserNotifications

/// Per-account Claude notifications: identifiers, thread, subtitle and state
/// keyed by account, so two accounts crossing the same threshold post two
/// banners, and the main account's alerts stay exactly the 6.1 ones.
@Suite("Notification scope per Claude account", .serialized)
struct NotificationScopeTests {

    private static let suiteName = "NotificationScopeTests"
    private let work = AccountID(rawValue: "acct-x")

    private func cleanDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        return defaults
    }

    private func workScope(name: String? = "Work", command: String? = "CLAUDE_CONFIG_DIR=~/.claude-work claude") -> NotificationScope {
        NotificationScope(account: work, displayName: { name }, loginCommand: { command })
    }

    private func toggles(resetReminders: Bool = false, claudeEnabled: Bool = true) -> NotificationToggles {
        NotificationToggles(
            masterEnabled: true,
            claudeEnabled: claudeEnabled,
            trackFiveHour: true, trackWeekly: true, trackSonnet: false, trackFable: false,
            sendRecovery: true, pacingHot: true, pacingWarning: false,
            resetReminderSession: resetReminders, resetReminderWeekly: resetReminders,
            resetReminderSessionOffsetMinutes: 15, resetReminderWeeklyOffsetMinutes: 60,
            extraCredits: true, tokenExpired: true,
            smartColorEnabled: false, smartColorProfile: .default,
            pacingMargin: 10, thresholds: .default,
            vendorDegraded: true, vendorRestored: true
        )
    }

    /// The body as the service composes it, through the same strings (the
    /// test bundle resolves them to their keys, the app to the copy).
    private func named(_ name: String, _ body: String) -> String {
        String(format: NSLocalizedString("notif.body.account.prefix", comment: ""), name, body)
    }

    private func snap(_ pct: Int) -> MetricSnapshot {
        MetricSnapshot(pct: pct, resetsAt: Date().addingTimeInterval(3600), windowDuration: 5 * 3600)
    }

    private func evaluate(_ service: NotificationService, fiveHour: Int, toggles: NotificationToggles? = nil) {
        service.evaluate(
            fiveHour: snap(fiveHour), sevenDay: snap(0), sonnet: snap(0), fable: snap(0),
            sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles ?? self.toggles()
        )
    }

    // MARK: - Main account

    @Test("the main account keeps the 6.1 identifier, subtitle and thread")
    func mainUnchanged() {
        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        state.levels["lastLevel_fiveHour"] = UsageLevel.orange.rawValue
        let service = NotificationService(center: center, stateStore: state)

        evaluate(service, fiveHour: 96)

        #expect(center.addedIDs == ["escalation_fiveHour"])
        let content = center.content(for: "escalation_fiveHour")
        #expect(content?.subtitle == "Claude")
        #expect(content?.threadIdentifier == "claude")
    }

    @Test("a main scope with no name to give reads exactly like no scope")
    func mainScopeWithoutNameIsAnonymous() {
        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        let service = NotificationService(
            center: center,
            stateStore: state,
            scope: NotificationScope(account: .main, displayName: { nil }, loginCommand: { nil })
        )

        service.notifyLoginExpired(since: Date(), toggles: toggles())

        #expect(center.addedIDs == ["token_expired"])
        let content = center.content(for: "token_expired")
        #expect(content?.subtitle == "Claude")
        #expect(content?.threadIdentifier == "claude")
        #expect(content?.body == String(localized: "notif.body.login.expired"))
    }

    // MARK: - Added account

    @Test("an added account suffixes its identifiers and names itself in its own thread")
    func addedAccountScoped() {
        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        state.levels["lastLevel_fiveHour"] = UsageLevel.orange.rawValue
        state.levels["lastLevel_extra"] = UsageLevel.green.rawValue
        state.pacings["lastPacing_fiveHour"] = PacingZone.onTrack.rawValue
        let service = NotificationService(center: center, stateStore: state, scope: workScope())

        service.evaluate(
            fiveHour: snap(96), sevenDay: snap(0), sonnet: snap(0), fable: snap(0),
            sessionPacing: .hot, weeklyPacing: nil,
            extraUsage: ExtraUsage(isEnabled: true, monthlyLimit: 100, usedCredits: 96, utilization: 96, currency: "USD", disabledReason: nil),
            toggles: toggles()
        )

        #expect(center.addedIDs.contains("escalation_fiveHour.acct-x"))
        #expect(center.addedIDs.contains("pacing_claude_hot.acct-x"))
        #expect(center.addedIDs.contains("escalation_extra.acct-x"))
        #expect(!center.addedIDs.contains("escalation_fiveHour"))
        for request in center.added {
            #expect(request.content.subtitle == "Claude · Work")
            #expect(request.content.threadIdentifier == "claude.acct-x")
        }
    }

    @Test("the expired-login alert names the account and hands over its folder's command")
    func loginExpiredNamesAccount() {
        let center = MockNotificationCenter()
        let service = NotificationService(center: center, stateStore: MockNotificationStateStore(), scope: workScope())

        service.notifyLoginExpired(since: Date(), toggles: toggles())

        #expect(center.addedIDs == ["token_expired.acct-x"])
        let renew = String(format: NSLocalizedString("notif.body.login.expired.dir", comment: ""),
                           "CLAUDE_CONFIG_DIR=~/.claude-work claude")
        #expect(center.content(for: "token_expired.acct-x")?.body == named("Work", renew))
    }

    @Test("the token alert of an added account is its own")
    func tokenAlertScoped() {
        let center = MockNotificationCenter()
        let service = NotificationService(center: center, stateStore: MockNotificationStateStore(), scope: workScope())

        service.notifyTokenExpired(toggles: toggles())

        #expect(center.addedIDs == ["token_expired.acct-x"])
        #expect(center.content(for: "token_expired.acct-x")?.body
                == named("Work", String(localized: "notif.body.token")))
    }

    @Test("a single running account keeps anonymous alerts even when added")
    func nameFollowsTheScope() {
        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        state.levels["lastLevel_fiveHour"] = UsageLevel.orange.rawValue
        let service = NotificationService(center: center, stateStore: state, scope: workScope(name: nil))

        evaluate(service, fiveHour: 96)

        let content = center.content(for: "escalation_fiveHour.acct-x")
        #expect(content?.subtitle == "Claude")
        #expect(content?.threadIdentifier == "claude.acct-x")
    }

    @Test("Codex and vendor alerts ignore the Claude account scope")
    func codexAndVendorUnscoped() {
        let center = MockNotificationCenter()
        let service = NotificationService(center: center, stateStore: MockNotificationStateStore(), scope: workScope())

        service.notifyCodexTokenExpired(toggles: toggles())

        #expect(center.addedIDs == ["codex_token_expired"])
        #expect(center.content(for: "codex_token_expired")?.threadIdentifier == "codex")
    }

    @Test("a test banner for an account looks like that account's real alerts")
    func accountTestBanner() {
        let center = MockNotificationCenter()
        let service = NotificationService(center: center, stateStore: MockNotificationStateStore())

        service.sendTest(forClaudeAccount: workScope())

        #expect(center.added.count == 1)
        #expect(center.added.first?.identifier.hasPrefix("test.acct-x_") == true)
        #expect(center.added.first?.content.subtitle == "Claude · Work")
        #expect(center.added.first?.content.threadIdentifier == "claude.acct-x")
    }

    // MARK: - Two accounts side by side

    @Test("two accounts crossing the same threshold both alert, without sharing id or state")
    func twoAccountsSameThreshold() {
        let defaults = cleanDefaults()
        let center = MockNotificationCenter()
        let mainState = UserDefaultsNotificationStateStore(defaults: defaults)
        let workState = UserDefaultsNotificationStateStore(defaults: defaults, keySuffix: work.storageSuffix)
        let main = NotificationService(
            center: center,
            stateStore: mainState,
            scope: NotificationScope(account: .main, displayName: { "Perso" })
        )
        let workService = NotificationService(center: center, stateStore: workState, scope: workScope())

        // Baselines at green, then both go red.
        evaluate(main, fiveHour: 10)
        evaluate(workService, fiveHour: 10)
        evaluate(main, fiveHour: 96)
        evaluate(workService, fiveHour: 96)

        #expect(center.addedIDs == ["escalation_fiveHour", "escalation_fiveHour.acct-x"])
        #expect(center.content(for: "escalation_fiveHour")?.subtitle == "Claude · Perso")
        #expect(center.content(for: "escalation_fiveHour.acct-x")?.subtitle == "Claude · Work")
        #expect(defaults.integer(forKey: "lastLevel_fiveHour") == UsageLevel.red.rawValue)
        #expect(defaults.integer(forKey: "lastLevel_fiveHour.acct-x") == UsageLevel.red.rawValue)

        // The main account easing off does not touch Work's state.
        evaluate(main, fiveHour: 10)
        #expect(defaults.integer(forKey: "lastLevel_fiveHour") == UsageLevel.green.rawValue)
        #expect(defaults.integer(forKey: "lastLevel_fiveHour.acct-x") == UsageLevel.red.rawValue)
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    @Test("Work's reset reminders never cancel the main account's")
    func remindersKeptApart() {
        let center = MockNotificationCenter()
        let workService = NotificationService(center: center, stateStore: MockNotificationStateStore(), scope: workScope())

        workService.scheduleResetReminders(
            sessionResetsAt: Date().addingTimeInterval(3 * 3600),
            weeklyResetsAt: Date().addingTimeInterval(3 * 86_400),
            toggles: toggles(resetReminders: true)
        )

        #expect(center.removedIDs == ["reminder_session.acct-x", "reminder_weekly.acct-x"])
        #expect(center.addedIDs == ["reminder_session.acct-x", "reminder_weekly.acct-x"])
        #expect(center.added.allSatisfy { $0.content.threadIdentifier == "claude.acct-x" })

        // Muted, the account drops its own reminders and nobody else's.
        workService.evaluate(
            fiveHour: snap(0), sevenDay: snap(0), sonnet: snap(0), fable: snap(0),
            sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles(claudeEnabled: false)
        )
        #expect(!center.removedIDs.contains("reminder_session"))
        #expect(!center.removedIDs.contains("reminder_weekly"))
    }

    // MARK: - Purge

    @Test("purging an account sweeps its pending and delivered alerts only")
    func purgeSweepsAccount() {
        let center = MockNotificationCenter()
        let service = NotificationService(center: center, stateStore: MockNotificationStateStore())

        service.purge(account: work, includingDelivered: true)

        #expect(center.removedIDs == NotificationService.claudeIdentifiers(for: work))
        #expect(center.removedDeliveredIDs == NotificationService.claudeIdentifiers(for: work))
        #expect(center.removedIDs.allSatisfy { $0.hasSuffix(".acct-x") })
        #expect(center.removedIDs.contains("reminder_session.acct-x"))
        #expect(center.removedIDs.contains("token_expired.acct-x"))
        #expect(center.removedIDs.contains("escalation_fiveHour.acct-x"))
    }

    @Test("a pause sweeps pending reminders but leaves the delivered banners")
    func purgePendingOnly() {
        let center = MockNotificationCenter()
        let service = NotificationService(center: center, stateStore: MockNotificationStateStore())

        service.purge(account: work, includingDelivered: false)

        #expect(!center.removedIDs.isEmpty)
        #expect(center.removedDeliveredIDs.isEmpty)
    }

    // MARK: - Per-account switch

    @Test("an account switched off is silenced alone; the others keep the app's settings")
    func switchMutesOneAccount() {
        let main = record("main", name: "Perso")
        var muted = record("acct-x", name: "Work", dir: "/Users/tester/.claude-work")
        muted.notificationsEnabled = false
        let base = toggles()

        #expect(base.scoped(to: main, tracksSeveralAccounts: true).claudeEnabled)
        #expect(!base.scoped(to: muted, tracksSeveralAccounts: true).claudeEnabled)
        // An account removed while a refresh was out sends nothing.
        #expect(!base.scoped(to: nil, tracksSeveralAccounts: true).claudeEnabled)
        #expect(!base.scoped(to: nil, tracksSeveralAccounts: false).claudeEnabled)
        // Everything else is the same bundle.
        #expect(base.scoped(to: muted, tracksSeveralAccounts: true).trackFiveHour == base.trackFiveHour)
        #expect(base.scoped(to: muted, tracksSeveralAccounts: true).codex == base.codex)
    }

    @Test("back to one account, a switch left off no longer mutes the main account")
    func singleAccountIgnoresSwitch() {
        var main = record("main", name: "Perso")
        main.notificationsEnabled = false
        let base = toggles()
        #expect(!base.scoped(to: main, tracksSeveralAccounts: true).claudeEnabled)
        #expect(base.scoped(to: main, tracksSeveralAccounts: false).claudeEnabled)

        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        state.levels["lastLevel_fiveHour"] = UsageLevel.orange.rawValue
        let service = NotificationService(center: center, stateStore: state)
        evaluate(service, fiveHour: 96, toggles: base.scoped(to: main, tracksSeveralAccounts: false))
        #expect(!center.addedIDs.isEmpty)
    }

    @Test("the Claude master off silences every account")
    func claudeMasterWins() {
        let base = toggles(claudeEnabled: false)
        #expect(!base.scoped(to: record("main", name: "Perso"), tracksSeveralAccounts: true).claudeEnabled)
        #expect(!base.scoped(to: record("main", name: "Perso"), tracksSeveralAccounts: false).claudeEnabled)
        #expect(!base.scoped(to: record("acct-x", name: "Work", dir: "/Users/tester/.claude-work"), tracksSeveralAccounts: true).claudeEnabled)
    }

    @Test("a muted account sends nothing and drops its own reminders")
    func mutedAccountSendsNothing() {
        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        state.levels["lastLevel_fiveHour"] = UsageLevel.orange.rawValue
        let service = NotificationService(center: center, stateStore: state, scope: workScope())
        var muted = record("acct-x", name: "Work", dir: "/Users/tester/.claude-work")
        muted.notificationsEnabled = false

        evaluate(service, fiveHour: 96, toggles: toggles().scoped(to: muted, tracksSeveralAccounts: true))

        #expect(center.addedIDs.isEmpty)
        #expect(center.removedIDs == ["reminder_session.acct-x", "reminder_weekly.acct-x"])
    }

    // MARK: - Labels

    private func record(_ id: String, name: String, dir: String? = nil, paused: Bool = false) -> ClaudeAccountRecord {
        ClaudeAccountRecord(
            id: id == "main" ? .main : AccountID(rawValue: id),
            configDir: dir,
            service: dir.map { _ in "Claude Code-credentials-12345678" },
            name: name,
            colorHex: "#5B8DEF",
            isPaused: paused
        )
    }

    @Test("alerts name their account only once two accounts run")
    func labelsFollowRunningCount() {
        let labels = AccountNotificationLabels()
        let home = "/Users/tester"

        labels.update([record("main", name: "Perso")], home: home)
        #expect(labels.name(for: .main) == nil)
        #expect(labels.loginCommand(for: .main) == nil)

        labels.update([record("main", name: "Perso"), record("acct-x", name: "Work", dir: "/Users/tester/.claude-work")], home: home)
        #expect(labels.scope(for: .main).displayName() == "Perso")
        #expect(labels.scope(for: work).displayName() == "Work")
        #expect(labels.scope(for: work).loginCommand() == "CLAUDE_CONFIG_DIR=~/.claude-work claude")

        labels.update([record("main", name: "Perso"), record("acct-x", name: "Work", dir: "/Users/tester/.claude-work", paused: true)], home: home)
        #expect(labels.name(for: .main) == nil)
    }

    @Test("a main account moved to its own folder renews with that folder's command")
    func mainCustomFolderCommand() {
        let labels = AccountNotificationLabels()
        labels.update([record("main", name: "Claude", dir: "/Users/tester/.claude-perso")], home: "/Users/tester")
        #expect(labels.loginCommand(for: .main) == "CLAUDE_CONFIG_DIR=~/.claude-perso claude")
        #expect(labels.name(for: .main) == nil)
    }
}

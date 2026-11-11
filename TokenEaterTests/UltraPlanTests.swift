import Testing
import Foundation

/// Claude Ultra: a weekly limit and no 5-hour session window. The fixtures
/// are the shape a live Ultra account returned on 2026-11-12, values and
/// identities replaced.
@Suite("Ultra plan (no session window)")
struct UltraPlanTests {

    static let ultraUsageJSON = """
    {
      "five_hour": null,
      "seven_day": {"utilization": 1.0, "resets_at": "2026-11-17T23:00:00.073403+00:00"},
      "seven_day_sonnet": null,
      "seven_day_opus": null,
      "extra_usage": {"is_enabled": false},
      "limits": [
        {"kind": "weekly_all", "group": "weekly", "percent": 1,
         "resets_at": "2026-11-17T23:00:00.073403+00:00", "scope": null, "is_active": true},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 0,
         "resets_at": "2026-11-17T23:00:00+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
      ]
    }
    """

    static let ultraProfileJSON = """
    {
      "account": {"uuid": "a", "full_name": "U", "display_name": "U", "email": "u@example.com",
                  "has_claude_max": true, "has_claude_pro": false},
      "organization": {"uuid": "o", "name": "Org", "organization_type": "claude_max",
                       "billing_type": "stripe_subscription", "rate_limit_tier": "default_claude_max_20x",
                       "plan_display_name": "Ultra", "plan_display_label": "Ultra plan"}
    }
    """

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Plan detection

    @Test("an Ultra profile is Ultra, not Max, although it reports has_claude_max")
    func ultraProfileIsUltra() throws {
        let profile = try decode(ProfileResponse.self, Self.ultraProfileJSON)
        #expect(profile.organization?.planDisplayName == "Ultra")
        #expect(PlanType(from: profile.account, organization: profile.organization) == .ultra)
        #expect(PlanType.ultra.displayLabel == "ULTRA")
        #expect(PlanType.ultra.lacksSessionWindow)
    }

    @Test("the label alone is enough when the name is missing")
    func labelFallback() {
        let account = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: true, hasClaudePro: false)
        let org = OrganizationInfo(uuid: "", name: "", organizationType: "claude_max", billingType: "",
                                   rateLimitTier: "default_claude_max_20x", planDisplayLabel: "Ultra plan")
        #expect(PlanType(from: account, organization: org) == .ultra)
    }

    @Test("a Max 20x profile without a plan name stays Max")
    func max20xStaysMax() throws {
        let json = Self.ultraProfileJSON
            .replacingOccurrences(of: #""plan_display_name": "Ultra", "plan_display_label": "Ultra plan""#,
                                  with: #""plan_display_name": "Max", "plan_display_label": "Max plan""#)
        let profile = try decode(ProfileResponse.self, json)
        #expect(PlanType(from: profile.account, organization: profile.organization) == .max)
        #expect(!PlanType.max.lacksSessionWindow)
    }

    @Test("a word merely containing ultra does not count")
    func wholeWordOnly() {
        let account = AccountInfo(uuid: "", fullName: "", displayName: "", email: "", hasClaudeMax: true, hasClaudePro: false)
        let org = OrganizationInfo(uuid: "", name: "", organizationType: "claude_max", billingType: "",
                                   rateLimitTier: "", planDisplayName: "Ultramarine")
        #expect(PlanType(from: account, organization: org) == .max)
    }

    @Test("an odd plan name type never costs the profile")
    func oddPlanNameIsLenient() throws {
        let json = Self.ultraProfileJSON
            .replacingOccurrences(of: #""plan_display_name": "Ultra""#, with: #""plan_display_name": 42"#)
        let profile = try decode(ProfileResponse.self, json)
        #expect(profile.organization?.planDisplayName == nil)
        // The label still says Ultra.
        #expect(PlanType(from: profile.account, organization: profile.organization) == .ultra)
    }

    @Test("an old profile with no plan name still decodes")
    func noPlanName() throws {
        let json = """
        {"account": {"uuid": "a", "full_name": "", "display_name": "", "email": "",
                     "has_claude_max": true, "has_claude_pro": false},
         "organization": {"uuid": "o", "name": "", "organization_type": "claude_max",
                          "billing_type": "", "rate_limit_tier": "default_claude_max_5x"}}
        """
        let profile = try decode(ProfileResponse.self, json)
        #expect(profile.organization?.planDisplayName == nil)
        #expect(PlanType(from: profile.account, organization: profile.organization) == .max)
    }

    // MARK: - Session window fact

    @Test("the Ultra response decodes with no session bucket and a weekly one")
    func ultraResponseShape() throws {
        let usage = try decode(UsageResponse.self, Self.ultraUsageJSON)
        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDay?.utilization == 1)
        #expect(usage.sevenDayFable?.utilization == 0)
    }

    @Test("the response decides once it carries a window, whatever the plan says")
    func responseDecides() throws {
        let ultra = try decode(UsageResponse.self, Self.ultraUsageJSON)
        #expect(!UsageStore.hasSessionWindow(usage: ultra, plan: .unknown))
        #expect(!UsageStore.hasSessionWindow(usage: ultra, plan: .max))
        // A plan named Ultra that does get a session bucket draws it.
        #expect(UsageStore.hasSessionWindow(usage: .fixture(), plan: .ultra))
    }

    @Test("before any usage, or with a degenerate one, the plan answers")
    func planFallback() {
        #expect(UsageStore.hasSessionWindow(usage: nil, plan: .unknown))
        #expect(UsageStore.hasSessionWindow(usage: nil, plan: .max))
        #expect(!UsageStore.hasSessionWindow(usage: nil, plan: .ultra))
        let empty = UsageResponse()
        #expect(UsageStore.hasSessionWindow(usage: empty, plan: .pro))
        #expect(!UsageStore.hasSessionWindow(usage: empty, plan: .ultra))
    }

    // MARK: - Weekly samples

    @Test("the weekly samples key follows the account suffix of the session key")
    func weeklyKey() {
        #expect(UsageStore.weeklySamplesKey(forSessionKey: "sessionPacingSamples") == "weeklyPacingSamples")
        #expect(UsageStore.weeklySamplesKey(forSessionKey: "sessionPacingSamples.acct-1234")
                == "weeklyPacingSamples.acct-1234")
        #expect(UsageStore.weeklySamplesKey(forSessionKey: "Tests.main") == "Tests.main.weekly")
    }

    @Test("minSpacing replaces the latest reading instead of piling up")
    func spacingThinsReadings() {
        let week: TimeInterval = 7 * 86_400
        let start = Date(timeIntervalSince1970: 1_000_000)
        let reset = start.addingTimeInterval(week)
        var samples: [PacingSample] = []
        // One reading every 5 minutes for a whole week.
        for step in 0..<(7 * 24 * 12) {
            samples = PacingSampleBuffer.append(
                samples, utilization: Double(step) / 20, resetDate: reset, windowDuration: week,
                now: start.addingTimeInterval(Double(step) * 300), minSpacing: UsageStore.weeklySampleSpacing
            )
        }
        #expect(samples.count <= PacingSampleBuffer.maxCount)
        // The whole week is still covered, from its first reading to the latest.
        #expect(samples.first?.date == start)
        #expect(samples.last?.date == start.addingTimeInterval(Double(7 * 24 * 12 - 1) * 300))
        // Every point but the latest stands at least the spacing from the next.
        for (a, b) in zip(samples.dropLast(2), samples.dropFirst().dropLast()) {
            #expect(b.date.timeIntervalSince(a.date) >= UsageStore.weeklySampleSpacing)
        }
    }

    @Test("no spacing keeps every reading, as the session buffer always did")
    func noSpacingKeepsAll() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(3600)
        var samples: [PacingSample] = []
        for step in 0..<5 {
            samples = PacingSampleBuffer.append(
                samples, utilization: Double(step), resetDate: reset, windowDuration: 5 * 3600,
                now: now.addingTimeInterval(Double(step) * 60)
            )
        }
        #expect(samples.count == 5)
    }
}

/// The store and the alerts on an Ultra response.
@Suite("Ultra plan, store and alerts", .serialized)
@MainActor
struct UltraPlanStoreTests {

    private static let samplesKey = "UltraPlanStoreTests.samples"

    private func cleanDefaults() {
        for key in [Self.samplesKey, UsageStore.weeklySamplesKey(forSessionKey: Self.samplesKey)] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func makeStore(usage: UsageResponse) -> (UsageStore, MockNotificationService) {
        cleanDefaults()
        let repo = MockUsageRepository()
        repo.stubbedUsage = usage
        let tokenProvider = MockTokenProvider()
        tokenProvider.token = "valid-token"
        let notif = MockNotificationService()
        let store = UsageStore(
            repository: repo,
            tokenProvider: tokenProvider,
            sharedFileService: MockSharedFileService(),
            notificationService: notif,
            sessionSamplesKey: Self.samplesKey,
            reloadWidgets: {}
        )
        store.notifTogglesProvider = {
            NotificationToggles(
                masterEnabled: true,
                trackFiveHour: true, trackWeekly: true, trackSonnet: true, trackFable: true,
                sendRecovery: true, pacingHot: true, pacingWarning: false,
                resetReminderSession: true, resetReminderWeekly: true,
                resetReminderSessionOffsetMinutes: 15, resetReminderWeeklyOffsetMinutes: 60,
                extraCredits: true, tokenExpired: true,
                smartColorEnabled: false, smartColorProfile: .default,
                pacingMargin: 10, thresholds: .default,
                vendorDegraded: true, vendorRestored: true
            )
        }
        return (store, notif)
    }

    @Test("an Ultra refresh has no session window, no 5h snapshot and no session reminder")
    func ultraRefresh() async throws {
        let usage = try JSONDecoder().decode(UsageResponse.self, from: Data(UltraPlanTests.ultraUsageJSON.utf8))
        let (store, notif) = makeStore(usage: usage)
        #expect(store.hasSessionWindow)   // nothing known yet

        await store.refresh()

        #expect(!store.hasSessionWindow)
        #expect(store.sevenDayPct == 1)
        #expect(store.fiveHourPacing == nil)
        #expect(notif.lastEvaluation != nil)
        #expect(notif.lastEvaluation?.fiveHour == nil)
        #expect(notif.lastEvaluation?.sevenDay.pct == 1)
        #expect(notif.lastReminderSchedule?.sessionResetsAt == nil)
        #expect(notif.lastReminderSchedule?.weeklyResetsAt != nil)
        // The week's first reading is recorded for the glance card's back.
        #expect(store.weeklySamples.count == 1)
        cleanDefaults()
    }

    @Test("a Max refresh keeps the session window")
    func maxRefresh() async {
        let (store, notif) = makeStore(usage: .fixture(fiveHourUtil: 12))
        await store.refresh()
        #expect(store.hasSessionWindow)
        #expect(notif.lastEvaluation?.fiveHour?.pct == 12)
        cleanDefaults()
    }

    @Test("losing the window drops the session curve kept from before")
    func staleSessionCurveDropped() async throws {
        let ultra = try JSONDecoder().decode(UsageResponse.self, from: Data(UltraPlanTests.ultraUsageJSON.utf8))
        let (store, _) = makeStore(usage: ultra)
        store.sessionSamples = [PacingSample(date: Date().addingTimeInterval(-60), utilization: 5)]
        UserDefaults.standard.set(Data("[]".utf8), forKey: Self.samplesKey)

        await store.refresh()

        #expect(store.sessionSamples.isEmpty)
        #expect(UserDefaults.standard.data(forKey: Self.samplesKey) == nil)
        cleanDefaults()
    }
}

@Suite("Ultra plan, notification service")
struct UltraPlanNotificationTests {

    @Test("no 5h snapshot sends nothing and leaves the stored session level alone")
    func nilSessionSnapshot() {
        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        state.levels["lastLevel_fiveHour"] = UsageLevel.orange.rawValue
        let service = NotificationService(center: center, stateStore: state)
        let toggles = NotificationToggles(
            masterEnabled: true,
            trackFiveHour: true, trackWeekly: true, trackSonnet: false, trackFable: false,
            sendRecovery: true, pacingHot: false, pacingWarning: false,
            resetReminderSession: false, resetReminderWeekly: false,
            resetReminderSessionOffsetMinutes: 15, resetReminderWeeklyOffsetMinutes: 60,
            extraCredits: false, tokenExpired: true,
            smartColorEnabled: false, smartColorProfile: .default,
            pacingMargin: 10, thresholds: .default,
            vendorDegraded: false, vendorRestored: false
        )
        service.evaluate(
            fiveHour: nil,
            sevenDay: MetricSnapshot(pct: 10, resetsAt: Date().addingTimeInterval(86_400), windowDuration: 7 * 86_400),
            sonnet: nil, fable: nil,
            sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles
        )
        #expect(!center.addedIDs.contains { $0.contains("fiveHour") })
        #expect(state.levels["lastLevel_fiveHour"] == UsageLevel.orange.rawValue)
    }
}

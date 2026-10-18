import Testing
import Foundation

/// A model-scoped weekly limit (Sonnet, Opus, Fable) exists only when the
/// account's response carries it. Anthropic stopped sending Sonnet and Opus
/// to most accounts, so every surface has to treat them as present-or-absent,
/// never as a permanent 0%.
@Suite("Model-scoped limits")
@MainActor
struct ModelScopedLimitTests {

    // MARK: - Decoding

    private func decode(_ json: String) throws -> UsageResponse {
        try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
    }

    @Test("a response without a Sonnet or Opus limit has neither")
    func absentLimits() throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": 12, "resets_at": null },
          "seven_day": { "utilization": 30, "resets_at": null },
          "seven_day_sonnet": null,
          "seven_day_opus": null,
          "limits": [
            { "kind": "weekly_scoped", "group": "weekly", "percent": 23, "resets_at": null,
              "scope": { "model": { "display_name": "Fable" } }, "is_active": true }
          ]
        }
        """)
        #expect(usage.sevenDaySonnet == nil)
        #expect(usage.sevenDayOpus == nil)
        #expect(usage.sevenDayFable != nil)
    }

    @Test("a flat seven_day_sonnet utilization is a Sonnet limit")
    func flatSonnet() throws {
        let usage = try decode(#"{ "seven_day_sonnet": { "utilization": 41, "resets_at": null } }"#)
        #expect(Int(usage.sevenDaySonnet?.utilization ?? -1) == 41)
    }

    @Test("a limits[] weekly_scoped entry tagged Sonnet or Opus is that limit")
    func scopedSonnetAndOpus() throws {
        let usage = try decode("""
        {
          "seven_day_sonnet": null,
          "limits": [
            { "kind": "weekly_scoped", "group": "weekly", "percent": 18, "resets_at": null,
              "scope": { "model": { "display_name": "Sonnet" } }, "is_active": true },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 7, "resets_at": null,
              "scope": { "model": { "display_name": "Opus" } }, "is_active": true }
          ]
        }
        """)
        #expect(Int(usage.sevenDaySonnet?.utilization ?? -1) == 18)
        #expect(Int(usage.sevenDayOpus?.utilization ?? -1) == 7)
    }

    private static func toggles(trackSonnet: Bool) -> NotificationToggles {
        NotificationToggles(
            masterEnabled: true,
            trackFiveHour: true, trackWeekly: true, trackSonnet: trackSonnet, trackFable: true,
            sendRecovery: false, pacingHot: false, pacingWarning: false,
            resetReminderSession: false, resetReminderWeekly: false,
            resetReminderSessionOffsetMinutes: 15, resetReminderWeeklyOffsetMinutes: 60,
            extraCredits: false, tokenExpired: false,
            smartColorEnabled: false, smartColorProfile: .default,
            pacingMargin: 10, thresholds: .default,
            vendorDegraded: false, vendorRestored: false
        )
    }

    // MARK: - Store presence

    private func makeStore(usage: UsageResponse) -> (UsageStore, MockNotificationService) {
        let repo = MockUsageRepository()
        repo.stubbedUsage = usage
        let token = MockTokenProvider()
        token.token = "t"
        let notif = MockNotificationService()
        let store = UsageStore(
            repository: repo,
            tokenProvider: token,
            sharedFileService: MockSharedFileService(),
            notificationService: notif,
            sessionSamplesKey: "ModelScopedLimitTests.samples",
            reloadWidgets: {}
        )
        store.notifTogglesProvider = { Self.toggles(trackSonnet: true) }
        return (store, notif)
    }

    @Test("no Sonnet limit: not present, and no Sonnet snapshot reaches the alerts")
    func storeWithoutSonnet() async {
        let (store, notif) = makeStore(usage: UsageResponse(
            fiveHour: UsageBucket(utilization: 20, resetsAt: nil),
            sevenDay: UsageBucket(utilization: 40, resetsAt: nil)
        ))
        await store.refresh(force: true)
        #expect(store.hasSonnet == false)
        #expect(store.hasOpus == false)
        #expect(notif.lastEvaluation != nil)
        #expect(notif.lastEvaluation?.sonnet == nil)
        // Fable is model-scoped too: absent, nothing reaches the alerts.
        #expect(notif.lastEvaluation?.fable == nil)
    }

    @Test("a Sonnet limit: present, and its snapshot reaches the alerts")
    func storeWithSonnet() async {
        let (store, notif) = makeStore(usage: UsageResponse(
            fiveHour: UsageBucket(utilization: 20, resetsAt: nil),
            sevenDay: UsageBucket(utilization: 40, resetsAt: nil),
            sevenDaySonnet: UsageBucket(utilization: 64, resetsAt: nil)
        ))
        await store.refresh(force: true)
        #expect(store.hasSonnet)
        #expect(notif.lastEvaluation?.sonnet?.pct == 64)
    }

    // MARK: - Menu bar

    private func renderData(_ segments: [MenuBarSegment], hasSonnet: Bool) -> MenuBarRenderer.RenderData {
        var data = MenuBarOutageBadgeTests.sampleRenderData(segments: segments)
        data.hasSonnet = hasSonnet
        return data
    }

    @Test("a Sonnet segment draws nothing without the limit and draws with it")
    func sonnetSegmentFollowsPresence() {
        let segments = [
            MenuBarSegment(kind: .session, style: .labelValue),
            MenuBarSegment(kind: .sonnet, style: .labelValue),
        ]
        let absent = MenuBarRenderer.renderWithHitRects(renderData(segments, hasSonnet: false))
        let present = MenuBarRenderer.renderWithHitRects(renderData(segments, hasSonnet: true))
        #expect(absent.hitRects.count == 1)
        #expect(present.hitRects.count == 2)

        // Alone in the bar and absent, it leaves the logo rather than a 0%.
        let alone = [MenuBarSegment(kind: .sonnet, style: .labelValue)]
        #expect(MenuBarRenderer.renderUncached(renderData(alone, hasSonnet: false)).isTemplate)
        #expect(MenuBarRenderer.renderUncached(renderData(alone, hasSonnet: true)).isTemplate == false)
    }

    @Test("Sonnet is presence-gated like Fable")
    func sonnetIsPresenceGated() {
        #expect(MenuBarSegmentKind.sonnet.isPresenceGated)
        #expect(MenuBarSegmentKind.fable.isPresenceGated)
    }

    // MARK: - Saved compositions

    @Test("a saved menu bar with a Sonnet segment keeps it, and it comes back once the limit does")
    func savedMenuBarKeepsSonnet() throws {
        let saved = MenuBarComposition(segments: [
            MenuBarSegment(kind: .session, style: .labelValue),
            MenuBarSegment(kind: .sonnet, style: .pill),
        ])
        let decoded = try JSONDecoder().decode(MenuBarComposition.self, from: JSONEncoder().encode(saved))
        #expect(decoded.segments.map(\.kind) == [.session, .sonnet])
        #expect(MenuBarRenderer.renderWithHitRects(renderData(decoded.segments, hasSonnet: false)).hitRects.count == 1)
        #expect(MenuBarRenderer.renderWithHitRects(renderData(decoded.segments, hasSonnet: true)).hitRects.count == 2)
    }

    @Test("a saved popover with a Sonnet element keeps it")
    func savedPopoverKeepsSonnet() throws {
        let saved = PopoverComposition(elements: [
            PopoverElement(kind: .session, style: .gaugeRing, width: .full),
            PopoverElement(kind: .sonnet, style: .gaugeRing, width: .third),
        ])
        let decoded = try JSONDecoder().decode(PopoverComposition.self, from: JSONEncoder().encode(saved))
        #expect(decoded.elements.map(\.kind) == [.session, .sonnet])
    }

    // MARK: - Defaults and templates

    @Test("no default layout or built-in template includes Sonnet")
    func templatesWithoutSonnet() {
        for template in MenuBarBuiltinTemplate.allCases {
            #expect(!template.composition.segments.contains { $0.kind == .sonnet }, "\(template.rawValue)")
        }
        for template in PopoverBuiltinTemplate.allCases {
            #expect(!template.composition.elements.contains { $0.kind == .sonnet }, "\(template.rawValue)")
        }
        #expect(!MenuBarComposition.default.segments.contains { $0.kind == .sonnet })
        #expect(!PopoverComposition.default.elements.contains { $0.kind == .sonnet })
    }

    @Test("a layout applied from Complete while it still had Sonnet still reads as Complete")
    func legacyCompleteStillMatches() {
        var menuBar = MenuBarBuiltinTemplate.complete.composition
        menuBar.segments.append(MenuBarSegment(kind: .sonnet, style: .labelValue))
        #expect(MenuBarBuiltinTemplate.complete.matches(menuBar))
        #expect(MenuBarBuiltinTemplate.complete.matches(MenuBarBuiltinTemplate.complete.composition))
        #expect(!MenuBarBuiltinTemplate.classic.matches(menuBar))
        // Sonnet anywhere else is a custom layout, not the old template.
        var moved = MenuBarBuiltinTemplate.complete.composition
        moved.segments.insert(MenuBarSegment(kind: .sonnet, style: .labelValue), at: 0)
        #expect(!MenuBarBuiltinTemplate.complete.matches(moved))

        var popover = PopoverBuiltinTemplate.complete.composition
        let weekly = popover.elements.firstIndex { $0.kind == .weekly }!
        popover.elements.insert(PopoverElement(kind: .sonnet, style: .gaugeRing, width: .third), at: weekly + 1)
        #expect(PopoverBuiltinTemplate.complete.matches(popover))
        #expect(PopoverBuiltinTemplate.complete.matches(PopoverBuiltinTemplate.complete.composition))
        #expect(!PopoverBuiltinTemplate.classic.matches(popover))
    }

    // MARK: - Notifications

    @Test("no Sonnet limit: no Sonnet alert and no Sonnet baseline, even when tracked")
    func noSonnetAlertWhenAbsent() {
        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        let service = NotificationService(center: center, stateStore: state)
        state.levels["lastLevel_sonnet"] = UsageLevel.green.rawValue
        let toggles = Self.toggles(trackSonnet: true)
        let calm = MetricSnapshot(pct: 5, resetsAt: nil, windowDuration: 5 * 3600)

        service.evaluate(fiveHour: calm, sevenDay: calm, sonnet: nil, fable: calm,
                         sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles)
        #expect(!center.addedIDs.contains { $0.contains("sonnet") })
        #expect(state.levels["lastLevel_sonnet"] == UsageLevel.green.rawValue)

        // The same alert fires once the limit is there and crosses a threshold.
        let hot = MetricSnapshot(pct: 96, resetsAt: nil, windowDuration: 7 * 86_400)
        service.evaluate(fiveHour: calm, sevenDay: calm, sonnet: hot, fable: calm,
                         sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles)
        #expect(center.addedIDs.contains { $0.contains("sonnet") })
    }

    @Test("no Fable limit: no Fable alert, and its baseline is left alone")
    func noFableAlertWhenAbsent() {
        let center = MockNotificationCenter()
        let state = MockNotificationStateStore()
        let service = NotificationService(center: center, stateStore: state)
        // Fable was high when it disappeared: a 0% stand-in would move that
        // baseline as if the pool had emptied.
        state.levels["lastLevel_fable"] = UsageLevel.red.rawValue
        let toggles = Self.toggles(trackSonnet: false)
        let calm = MetricSnapshot(pct: 5, resetsAt: nil, windowDuration: 5 * 3600)

        service.evaluate(fiveHour: calm, sevenDay: calm, sonnet: nil, fable: nil,
                         sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles)
        #expect(!center.addedIDs.contains { $0.contains("fable") })
        #expect(state.levels["lastLevel_fable"] == UsageLevel.red.rawValue)

        let hot = MetricSnapshot(pct: 96, resetsAt: nil, windowDuration: 7 * 86_400)
        state.levels["lastLevel_fable"] = UsageLevel.green.rawValue
        service.evaluate(fiveHour: calm, sevenDay: calm, sonnet: nil, fable: hot,
                         sessionPacing: nil, weeklyPacing: nil, extraUsage: nil, toggles: toggles)
        #expect(center.addedIDs.contains { $0.contains("fable") })
    }
}

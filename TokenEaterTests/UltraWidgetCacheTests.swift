import Testing
import Foundation

/// What the widget reads of an account on a plan with no 5-hour window
/// (Ultra): the app writes the decoded response into the shared file with the
/// synthesized `Encodable`, and the widget decodes it back. The widget tells
/// Ultra apart only by `fiveHour == nil && sevenDay != nil`, so that has to
/// survive the round trip, and a plan with the session window must keep it.
@Suite("Ultra widget cache")
struct UltraWidgetCacheTests {

    static let ultraUsageJSON = """
    {
      "five_hour": null,
      "seven_day": {"utilization": 12.0, "resets_at": "2026-11-17T23:00:00.073403+00:00"},
      "seven_day_sonnet": null,
      "seven_day_opus": null,
      "extra_usage": {"is_enabled": false},
      "limits": [
        {"kind": "weekly_all", "group": "weekly", "percent": 12,
         "resets_at": "2026-11-17T23:00:00.073403+00:00", "scope": null, "is_active": true},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 4,
         "resets_at": "2026-11-17T23:00:00+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
      ]
    }
    """

    static let maxUsageJSON = """
    {
      "five_hour": {"utilization": 37.0, "resets_at": "2026-11-12T18:00:00+00:00"},
      "seven_day": {"utilization": 21.0, "resets_at": "2026-11-17T23:00:00+00:00"},
      "seven_day_sonnet": null,
      "seven_day_opus": null,
      "limits": [
        {"kind": "session", "group": "session", "percent": 37,
         "resets_at": "2026-11-12T18:00:00+00:00", "scope": null, "is_active": true},
        {"kind": "weekly_all", "group": "weekly", "percent": 21,
         "resets_at": "2026-11-17T23:00:00+00:00", "scope": null, "is_active": true}
      ]
    }
    """

    private func decodeUsage(_ json: String) throws -> UsageResponse {
        try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
    }

    /// The trip through the shared file: wrapped as the app caches it,
    /// encoded, then decoded the way the widget reads it.
    private func roundTrip(_ usage: UsageResponse) throws -> UsageResponse {
        let cached = CachedUsage(usage: usage, fetchDate: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try JSONEncoder().encode(cached)
        return try JSONDecoder().decode(CachedUsage.self, from: data).usage
    }

    // MARK: - Shared-file round trip

    @Test("an Ultra response keeps no session, its week and its Fable limit through the cache")
    func ultraRoundTrip() throws {
        let decoded = try decodeUsage(Self.ultraUsageJSON)
        #expect(decoded.fiveHour == nil)
        #expect(decoded.sevenDay != nil)
        #expect(decoded.sevenDayFable != nil)

        let cached = try roundTrip(decoded)
        #expect(cached.fiveHour == nil)
        #expect(cached.sevenDay?.utilization == 12)
        #expect(cached.sevenDay?.resetsAtDate != nil)
        #expect(cached.sevenDayFable?.utilization == 4)
        #expect(cached.sevenDayFable?.resetsAtDate != nil)
    }

    @Test("a Max response keeps its session window through the cache")
    func maxRoundTrip() throws {
        let cached = try roundTrip(try decodeUsage(Self.maxUsageJSON))
        #expect(cached.fiveHour?.utilization == 37)
        #expect(cached.fiveHour?.resetsAtDate != nil)
        #expect(cached.sevenDay?.utilization == 21)
        #expect(cached.sevenDayFable == nil)
    }

    // MARK: - Which windows the rings draw

    @Test("the single ring shows the week on Ultra, from the cached response")
    func ultraPrimaryIsWeekly() throws {
        let cached = try roundTrip(try decodeUsage(Self.ultraUsageJSON))
        let window = WidgetUsageWindow.primary(for: cached)
        #expect(window == .weekly)
        #expect(window?.windowDuration == TimeInterval(7 * 86_400))
        #expect(window?.isMultiDay == true)
        #expect(window?.bucket(in: cached)?.utilization == 12)
    }

    @Test("the single ring keeps the session on Max")
    func maxPrimaryIsSession() throws {
        let cached = try roundTrip(try decodeUsage(Self.maxUsageJSON))
        let window = WidgetUsageWindow.primary(for: cached)
        #expect(window == .session)
        #expect(window?.windowDuration == TimeInterval(5 * 3600))
        #expect(window?.isMultiDay == false)
    }

    @Test("no window at all draws no ring rather than waiting for one")
    func noWindowHasNoPrimary() {
        let usage = UsageResponse()
        #expect(WidgetUsageWindow.primary(for: usage) == nil)
        #expect(WidgetUsageWindow.mediumRings(for: usage).isEmpty)
    }

    @Test("Ultra's Overview puts the week first, then Fable in the session's place")
    func ultraMediumRings() throws {
        let cached = try roundTrip(try decodeUsage(Self.ultraUsageJSON))
        #expect(WidgetUsageWindow.mediumRings(for: cached) == [.weekly, .fable])
        #expect(WidgetUsageWindow.fable.windowDuration == 7 * 86_400)
    }

    @Test("without Fable, Ultra's Overview has the week alone before pacing")
    func ultraWithoutFable() {
        let usage = UsageResponse(sevenDay: UsageBucket(utilization: 30, resetsAt: nil))
        #expect(WidgetUsageWindow.mediumRings(for: usage) == [.weekly])
    }

    @Test("Max's Overview stays session then week, even when it has a Fable limit")
    func maxMediumRingsUnchanged() throws {
        let cached = try roundTrip(try decodeUsage(Self.maxUsageJSON))
        #expect(WidgetUsageWindow.mediumRings(for: cached) == [.session, .weekly])

        let withFable = UsageResponse(
            fiveHour: UsageBucket(utilization: 10, resetsAt: nil),
            sevenDay: UsageBucket(utilization: 20, resetsAt: nil),
            sevenDayFable: UsageBucket(utilization: 30, resetsAt: nil)
        )
        #expect(WidgetUsageWindow.mediumRings(for: withFable) == [.session, .weekly])
    }
}

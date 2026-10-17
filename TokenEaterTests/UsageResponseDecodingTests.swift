import Testing
import Foundation

@Suite("UsageResponse decoding")
struct UsageResponseDecodingTests {

    /// extra_usage gained a `disabled_reason` field explaining why the lane is off.
    @Test("decodes extra_usage.disabled_reason")
    func decodesExtraUsageDisabledReason() throws {
        let json = """
        {
          "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null, "currency": null, "disabled_reason": "org_level_disabled" }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(usage.extraUsage?.disabledReason == "org_level_disabled")
    }

    /// `percent` prefers the API-provided utilization when present. Drives the
    /// menu-bar "EC %", the widget ring, and the dashboard tile, so it must
    /// round the same way everywhere.
    @Test("ExtraUsage.percent prefers API utilization")
    func extraPercentPrefersUtilization() {
        let extra = ExtraUsage(
            isEnabled: true, monthlyLimit: 50000, usedCredits: 18000,
            utilization: 36.0, currency: "USD", disabledReason: nil
        )
        #expect(extra.percent == 36)
    }

    /// When the API omits `utilization`, `percent` falls back to used / limit.
    @Test("ExtraUsage.percent falls back to used / limit")
    func extraPercentFallsBackToRatio() {
        let extra = ExtraUsage(
            isEnabled: true, monthlyLimit: 50000, usedCredits: 18000,
            utilization: nil, currency: "USD", disabledReason: nil
        )
        #expect(extra.percent == 36)
    }

    /// No limit to divide by → 0, never a divide-by-zero / NaN.
    @Test("ExtraUsage.percent is 0 with no limit")
    func extraPercentZeroWithoutLimit() {
        let extra = ExtraUsage(
            isEnabled: true, monthlyLimit: nil, usedCredits: 18000,
            utilization: nil, currency: "USD", disabledReason: nil
        )
        #expect(extra.percent == 0)
    }

    /// Enabled with no monthly limit is uncapped: surfaces show the spend, not 0 %.
    /// The real payload from an org seat: `is_enabled` true, no `monthly_limit`.
    @Test("ExtraUsage.isUncapped when enabled with no limit")
    func extraUncapped() throws {
        let json = #"{"is_enabled": true, "used_credits": 2049, "currency": "USD"}"#
        let extra = try JSONDecoder().decode(ExtraUsage.self, from: Data(json.utf8))
        #expect(extra.isUncapped)
        #expect(extra.percent == 0)
        #expect(!ExtraUsage(isEnabled: true, monthlyLimit: 1000, usedCredits: 0, utilization: 0, currency: "AUD", disabledReason: nil).isUncapped)
        #expect(!ExtraUsage(isEnabled: false, monthlyLimit: nil, usedCredits: 0, utilization: nil, currency: "USD", disabledReason: "out_of_credits").isUncapped)
    }

    /// The text the menu bar and the popover show in place of the percentage:
    /// present only when uncapped, so the capped case draws what it always did.
    @Test("ExtraUsage.uncappedSpendText only when uncapped")
    func uncappedSpendText() {
        #expect(ExtraUsage.fixture(monthlyLimit: nil, usedCredits: 2049, utilization: nil).uncappedSpendText == "$20.49")
        #expect(ExtraUsage.fixture(monthlyLimit: 0, usedCredits: 123456, utilization: nil).uncappedSpendText == "$1,235")
        #expect(ExtraUsage.fixture(monthlyLimit: nil, usedCredits: nil, utilization: nil).uncappedSpendText == "$0.00")
        #expect(ExtraUsage.fixture(monthlyLimit: 40000, usedCredits: 27000).uncappedSpendText == nil)
        #expect(ExtraUsage.fixture(isEnabled: false, monthlyLimit: nil, usedCredits: 2049, utilization: nil).uncappedSpendText == nil)
    }

    /// Picks the uncapped colour: neutral at zero, warning once money is spent.
    /// A capped or disabled pool never counts, so its colour is untouched.
    @Test("ExtraUsage.hasUncappedSpend only when uncapped and above zero")
    func hasUncappedSpend() {
        #expect(ExtraUsage.fixture(monthlyLimit: nil, usedCredits: 2049, utilization: nil).hasUncappedSpend)
        #expect(!ExtraUsage.fixture(monthlyLimit: nil, usedCredits: 0, utilization: nil).hasUncappedSpend)
        #expect(!ExtraUsage.fixture(monthlyLimit: nil, usedCredits: nil, utilization: nil).hasUncappedSpend)
        #expect(!ExtraUsage.fixture(monthlyLimit: 40000, usedCredits: 27000).hasUncappedSpend)
        #expect(!ExtraUsage.fixture(isEnabled: false, monthlyLimit: nil, usedCredits: 2049, utilization: nil).hasUncappedSpend)
    }

    /// Unfamiliar top-level keys (new server-side codenames) must not break decoding.
    @Test("unknown top-level keys are ignored")
    func unknownKeysIgnored() throws {
        let json = """
        {
          "five_hour": { "utilization": 1.0, "resets_at": null },
          "some_codename": { "whatever": true },
          "another_codename": null,
          "brand_new_codename": { "nested": { "x": 1 } }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(usage.fiveHour?.utilization == 1.0)
    }

    // MARK: - Live contract hardening

    private func decode(_ json: String) throws -> UsageResponse {
        try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
    }

    /// Synthetic mirror of the full live `/api/oauth/usage` shape (fake values):
    /// money objects under `spend`, `weekly_scoped_shares`, `locked_reason`,
    /// `scope.surface` and the extended `extra_usage` must not break anything.
    @Test("decodes a payload mirroring the full live shape")
    func decodesFullLiveShape() throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": 37.0, "resets_at": "2026-10-13T18:00:00.123456+00:00",
                         "limit_dollars": null, "remaining_dollars": null, "used_dollars": null,
                         "locked_reason": null },
          "seven_day": { "utilization": 21.0, "resets_at": "2026-10-17T07:00:00.123456+00:00",
                         "limit_dollars": null, "remaining_dollars": null, "used_dollars": null,
                         "locked_reason": null },
          "limits": [
            { "kind": "session", "group": "session", "percent": 37,
              "resets_at": "2026-10-13T18:00:00.123456+00:00", "scope": null,
              "severity": "normal", "is_active": true },
            { "kind": "weekly_all", "group": "weekly", "percent": 21,
              "resets_at": "2026-10-17T07:00:00.123456+00:00", "scope": null,
              "severity": "normal", "is_active": false },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 12,
              "resets_at": "2026-10-17T07:00:00.123456+00:00",
              "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
              "severity": "normal", "is_active": false }
          ],
          "weekly_scoped_shares": [
            { "limit_index": 2, "allowance_percent_of_weekly": 50, "used_percent_of_weekly": 6 }
          ],
          "spend": {
            "enabled": false, "can_toggle": true, "can_purchase_credits": false,
            "percent": 0, "severity": "normal", "disclaimer": "Fake disclaimer.",
            "disabled_reason": null, "auto_reload": null, "balance": null, "cap": null, "limit": null,
            "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 }
          },
          "extra_usage": {
            "is_enabled": false, "credits_ever_enabled": false, "user_disabled": false,
            "spend_limit_reached": false, "monthly_limit": null, "used_credits": null,
            "utilization": null, "currency": null, "decimal_places": null,
            "daily": null, "weekly": null, "disabled_reason": null
          },
          "member_dashboard_available": false
        }
        """)
        #expect(usage.fiveHour?.utilization == 37)
        #expect(usage.fiveHour?.resetsAtDate != nil)
        #expect(usage.sevenDay?.utilization == 21)
        #expect(usage.sevenDayFable?.utilization == 12)
        #expect(usage.sevenDayFable?.resetsAtDate != nil)
        #expect(usage.sevenDaySonnet == nil)
        #expect(usage.sevenDayOpus == nil)
        #expect(usage.extraUsage?.isEnabled == false)
    }

    /// `limits[].percent` arrives as a JSON integer; it must land in the Double.
    @Test("limits[].percent decodes from a JSON integer")
    func limitPercentDecodesFromInt() throws {
        let limit = try JSONDecoder().decode(
            UsageLimit.self,
            from: Data(#"{ "kind": "weekly_scoped", "percent": 42 }"#.utf8)
        )
        #expect(limit.percent == 42.0)
    }

    /// One malformed entry must not wipe the whole array and, with it, every
    /// per-model fallback.
    @Test("a malformed limits[] entry does not drop its siblings")
    func malformedLimitEntryIsSkipped() throws {
        let usage = try decode("""
        {
          "limits": [
            "garbage", 42, null,
            { "kind": 7, "percent": { "nested": true }, "resets_at": [], "scope": "weird" },
            { "kind": "weekly_scoped", "percent": 23, "resets_at": null,
              "scope": { "model": { "id": 99, "display_name": "Fable" }, "surface": { "x": 1 } } }
          ]
        }
        """)
        #expect(usage.sevenDayFable?.utilization == 23)
    }

    @Test("null five_hour and seven_day fall back to limits[] session and weekly_all")
    func mainGaugesFallBackToLimits() throws {
        let usage = try decode("""
        {
          "five_hour": null,
          "limits": [
            { "kind": "session", "percent": 37, "resets_at": "2026-10-13T18:00:00Z", "scope": null },
            { "kind": "weekly_all", "percent": 21, "resets_at": "2026-10-17T07:00:00Z", "scope": null }
          ]
        }
        """)
        #expect(usage.fiveHour?.utilization == 37)
        #expect(usage.fiveHour?.resetsAt == "2026-10-13T18:00:00Z")
        #expect(usage.sevenDay?.utilization == 21)
        #expect(usage.sevenDay?.resetsAt == "2026-10-17T07:00:00Z")
    }

    @Test("five_hour and seven_day keys win over limits[]")
    func mainGaugeRootKeysWin() throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": 50, "resets_at": "2026-10-13T18:00:00Z" },
          "seven_day": { "utilization": 60, "resets_at": "2026-10-17T07:00:00Z" },
          "limits": [
            { "kind": "session", "percent": 1, "resets_at": "2026-01-01T00:00:00Z", "scope": null },
            { "kind": "weekly_all", "percent": 2, "resets_at": "2026-01-01T00:00:00Z", "scope": null }
          ]
        }
        """)
        #expect(usage.fiveHour?.utilization == 50)
        #expect(usage.fiveHour?.resetsAt == "2026-10-13T18:00:00Z")
        #expect(usage.sevenDay?.utilization == 60)
        #expect(usage.sevenDay?.resetsAt == "2026-10-17T07:00:00Z")
    }

    /// Only an entry with no scope at all is the account-wide pool: a model,
    /// a surface, or a scope too malformed to read all disqualify it.
    @Test("a scoped limits[] entry never backs five_hour or seven_day", arguments: [
        #"{ "model": { "display_name": "Fable" } }"#,
        #"{ "model": null, "surface": "claude_code" }"#,
        #"{ "model": "fable" }"#,
        #""weird""#,
        "{}",
    ])
    func scopedEntryDoesNotBackPools(scope: String) throws {
        let usage = try decode("""
        {
          "limits": [
            { "kind": "session", "percent": 80, "scope": \(scope) },
            { "kind": "weekly_all", "percent": 70, "scope": \(scope) }
          ]
        }
        """)
        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDay == nil)
    }

    /// An absent scope key counts as unscoped, like an explicit null.
    @Test("a limits[] entry with no scope key backs five_hour")
    func missingScopeKeyIsUnscoped() throws {
        let usage = try decode("""
        { "limits": [ { "kind": "session", "percent": 80 } ] }
        """)
        #expect(usage.fiveHour?.utilization == 80)
    }

    /// A first match with no percentage must not hide a later valid one.
    @Test("a matching limits[] entry with a null percent does not hide a valid one")
    func nullPercentEntryDoesNotShadowValidOne() throws {
        let usage = try decode("""
        {
          "limits": [
            { "kind": "session", "percent": null, "scope": null },
            { "kind": "session", "percent": 44, "scope": null },
            { "kind": "weekly_scoped", "percent": null, "scope": { "model": { "display_name": "Fable" } } },
            { "kind": "weekly_scoped", "percent": 9, "scope": { "model": { "display_name": "Fable" } } }
          ]
        }
        """)
        #expect(usage.fiveHour?.utilization == 44)
        #expect(usage.sevenDayFable?.utilization == 9)
    }

    /// Unknown is not 0%: a null utilization with nothing to fill it leaves the
    /// bucket absent rather than a gauge reading 0.
    @Test("null utilization without a fallback is absent, not 0%")
    func nullUtilizationIsAbsent() throws {
        let usage = try decode("""
        { "five_hour": { "utilization": null, "resets_at": "2026-10-13T18:00:00Z" },
          "seven_day": { "utilization": 0, "resets_at": null } }
        """)
        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDay?.utilization == 0)
    }

    /// A null utilization no longer discards the bucket's reset time: limits[]
    /// fills the percentage and, having no reset of its own, keeps the flat one.
    @Test("null utilization is filled from limits[] and keeps its own reset")
    func nullUtilizationFilledFromLimits() throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": null, "resets_at": "2026-10-13T18:00:00Z" },
          "limits": [
            { "kind": "session", "percent": 37, "resets_at": null, "scope": null }
          ]
        }
        """)
        #expect(usage.fiveHour?.utilization == 37)
        #expect(usage.fiveHour?.resetsAt == "2026-10-13T18:00:00Z")
    }

    /// When limits[] supplies the percentage, its own reset goes with it.
    @Test("a limits[] fallback brings its own reset over the flat one")
    func fallbackResetLeads() throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": null, "resets_at": "2026-10-13T18:00:00Z" },
          "limits": [
            { "kind": "session", "percent": 37, "resets_at": "2026-10-13T19:00:00Z", "scope": null }
          ]
        }
        """)
        #expect(usage.fiveHour?.utilization == 37)
        #expect(usage.fiveHour?.resetsAt == "2026-10-13T19:00:00Z")
    }

    /// A complete flat key wins whole: its null reset (no window open) is not
    /// replaced by a date from limits[], which would invent a countdown.
    @Test("a flat key with a utilization keeps its null reset")
    func flatNullResetIsKept() throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": 0, "resets_at": null },
          "limits": [
            { "kind": "session", "percent": 0, "resets_at": "2026-10-13T19:00:00Z", "scope": null }
          ]
        }
        """)
        #expect(usage.fiveHour?.utilization == 0)
        #expect(usage.fiveHour?.resetsAt == nil)
    }

    /// A limits[] entry with no percentage must not become a 0% bucket.
    @Test("limits[] entry with a null percent adds no bucket")
    func nullPercentAddsNoBucket() throws {
        let usage = try decode("""
        {
          "limits": [
            { "kind": "session", "percent": null, "scope": null },
            { "kind": "weekly_scoped", "percent": null,
              "scope": { "model": { "display_name": "Fable" } } }
          ]
        }
        """)
        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDayFable == nil)
    }

    @Test("numeric resets_at keeps the bucket and parses as epoch seconds or ms")
    func numericResetsAt() throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": 10, "resets_at": 1760378400 },
          "seven_day": { "utilization": 20.5, "resets_at": 1760684400000 }
        }
        """)
        #expect(usage.fiveHour?.utilization == 10)
        #expect(usage.fiveHour?.resetsAtDate == Date(timeIntervalSince1970: 1_760_378_400))
        #expect(usage.sevenDay?.utilization == 20.5)
        #expect(usage.sevenDay?.resetsAtDate == Date(timeIntervalSince1970: 1_760_684_400))
    }

    /// Strings are not numbers: "NaN" or "inf" would otherwise become a
    /// present bucket and trap in the stores' `Int(...)` conversions.
    @Test("a string utilization leaves the bucket absent", arguments: ["NaN", "inf", "-inf", "1e400", "42"])
    func stringUtilizationIsAbsent(value: String) throws {
        let usage = try decode("""
        {
          "five_hour": { "utilization": "\(value)", "resets_at": null },
          "limits": [ { "kind": "weekly_scoped", "percent": "\(value)",
                        "scope": { "model": { "display_name": "Fable" } } } ]
        }
        """)
        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDayFable == nil)
    }

    /// The cache and `UsageBucket.fixture` rely on a direct decode still
    /// rejecting a bucket with no utilization.
    @Test("UsageBucket decoded directly throws without a utilization", arguments: [
        #"{ "utilization": null, "resets_at": "2026-10-13T18:00:00Z" }"#,
        #"{ "resets_at": "2026-10-13T18:00:00Z" }"#,
        #"{ "utilization": "NaN" }"#,
    ])
    func directBucketDecodeThrows(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UsageBucket.self, from: Data(json.utf8))
        }
    }

    /// The cache in shared.json re-decodes through the same init: buckets that
    /// came from limits[] must survive the round trip as plain keys.
    @Test("fallback buckets survive the shared-file cache round trip")
    func cacheRoundTrip() throws {
        let usage = try decode("""
        {
          "limits": [
            { "kind": "session", "percent": 37, "resets_at": "2026-10-13T18:00:00Z", "scope": null },
            { "kind": "weekly_scoped", "percent": 12, "resets_at": null,
              "scope": { "model": { "display_name": "Fable" } } }
          ]
        }
        """)
        let cached = CachedUsage(usage: usage, fetchDate: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(cached)
        let decoded = try JSONDecoder().decode(CachedUsage.self, from: data)
        #expect(decoded.usage.fiveHour?.utilization == 37)
        #expect(decoded.usage.fiveHour?.resetsAt == "2026-10-13T18:00:00Z")
        #expect(decoded.usage.sevenDayFable?.utilization == 12)
    }
}

import Testing
import Foundation

@Suite("UsageResponse decoding")
struct UsageResponseDecodingTests {

    /// Anthropic moved the Claude Design quota from `seven_day_omelette` to
    /// `omelette_promotional` during a rollout (the old key now returns null).
    /// The Design card must keep working by falling back to the new key.
    @Test("decodes Design from omelette_promotional when seven_day_omelette is null")
    func decodesDesignFromPromotionalKey() throws {
        let json = """
        {
          "five_hour": { "utilization": 1.0, "resets_at": "2026-05-31T19:20:01.093372+00:00" },
          "seven_day": { "utilization": 6.0, "resets_at": "2026-06-06T10:00:01.093397+00:00" },
          "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
          "seven_day_omelette": null,
          "tangelo": null,
          "iguana_necktie": null,
          "omelette_promotional": { "utilization": 12.0, "resets_at": "2026-06-06T10:00:01+00:00" },
          "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null, "currency": null, "disabled_reason": "org_level_disabled" }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(usage.sevenDayDesign?.utilization == 12.0)
    }

    /// Regression guard: accounts still on the old key must keep working.
    @Test("decodes Design from legacy seven_day_omelette key")
    func decodesDesignFromLegacyKey() throws {
        let json = """
        {
          "seven_day_omelette": { "utilization": 33.0, "resets_at": null }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(usage.sevenDayDesign?.utilization == 33.0)
    }

    /// The legacy key wins when both are present (it's the canonical pool;
    /// promotional is a supplemental allotment that surfaces only post-rollout).
    @Test("legacy seven_day_omelette takes precedence over promotional")
    func legacyKeyTakesPrecedence() throws {
        let json = """
        {
          "seven_day_omelette": { "utilization": 50.0, "resets_at": null },
          "omelette_promotional": { "utilization": 12.0, "resets_at": null }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(usage.sevenDayDesign?.utilization == 50.0)
    }

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

    /// New unknown codenames (tangelo, iguana_necktie) must not break decoding.
    @Test("unknown top-level keys are ignored")
    func unknownKeysIgnored() throws {
        let json = """
        {
          "five_hour": { "utilization": 1.0, "resets_at": null },
          "tangelo": { "whatever": true },
          "iguana_necktie": null,
          "brand_new_codename": { "nested": { "x": 1 } }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(usage.fiveHour?.utilization == 1.0)
    }
}

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
}

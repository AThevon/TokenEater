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
}

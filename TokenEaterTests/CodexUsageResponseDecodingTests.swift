import Testing
import Foundation

@Suite("CodexUsageResponse decoding")
struct CodexUsageResponseDecodingTests {

    // MARK: - Plan shapes

    @Test("weekly-only plan decodes its single window as the primary one")
    func proliteShape() {
        let usage = CodexFixtures.decode(CodexFixtures.proliteJSON)

        #expect(usage.planType == "prolite")
        #expect(usage.rateLimit?.primaryWindow?.limitWindowSeconds == 604_800)
        #expect(usage.rateLimit?.primaryWindow?.usedPercent == 18)
        #expect(usage.rateLimit?.secondaryWindow == nil)
        #expect(usage.rateLimit?.windows.count == 1)
    }

    @Test("session + weekly plan decodes both windows")
    func plusShape() {
        let usage = CodexFixtures.decode(CodexFixtures.plusJSON)

        #expect(usage.rateLimit?.windows.count == 2)
        #expect(usage.rateLimit?.primaryWindow?.limitWindowSeconds == 18_000)
        #expect(usage.rateLimit?.secondaryWindow?.limitWindowSeconds == 604_800)
        #expect(usage.rateLimit?.secondaryWindow?.usedPercent == 63)
    }

    @Test("API-key account has no rate limit object and no windows")
    func apiKeyShape() {
        let usage = CodexFixtures.decode(CodexFixtures.apiKeyJSON)

        #expect(usage.rateLimit == nil)
        #expect(usage.planType == nil)
        #expect(CodexWindowResolver.windows(in: usage).isEmpty)
    }

    // MARK: - Tolerance

    @Test("a malformed entry is dropped without costing the rest of the response")
    func lossyAdditionalLimits() {
        let usage = CodexFixtures.decode(CodexFixtures.limitReachedJSON)

        #expect(usage.planType == "pro")
        #expect(usage.additionalRateLimits.isEmpty)
        #expect(usage.rateLimit?.primaryWindow?.usedPercent == 100)
    }

    @Test("rate_limit_reached_type decodes from both the object and the string shape")
    func reachedTypeShapes() {
        let nested = CodexFixtures.decode(CodexFixtures.limitReachedJSON)
        #expect(nested.rateLimitReachedType == "rate_limit_reached")

        let flat = CodexFixtures.decode("""
        { "rate_limit_reached_type": "workspace_owner_credits_depleted" }
        """)
        #expect(flat.rateLimitReachedType == "workspace_owner_credits_depleted")

        let absent = CodexFixtures.decode(CodexFixtures.plusJSON)
        #expect(absent.rateLimitReachedType == nil)
    }

    @Test("unknown top-level keys are ignored")
    func unknownKeys() {
        let usage = CodexFixtures.decode("""
        { "plan_type": "team", "brand_new_field": { "nested": [1, 2] }, "rate_limit": null }
        """)
        #expect(usage.planType == "team")
    }

    @Test("credits balance stays a string and converts on demand")
    func creditsBalance() {
        let usage = CodexFixtures.decode(CodexFixtures.plusJSON)

        #expect(usage.credits?.balance == "12.50")
        #expect(usage.credits?.numericBalance == 12.5)
        #expect(usage.credits?.hasCredits == true)
        #expect(usage.credits?.isPresentable == true)
    }

    @Test("banked reset credits are read from the nested API object")
    func resetCredits() {
        let usage = CodexFixtures.decode(CodexFixtures.proliteJSON)
        #expect(usage.resetCreditsAvailable == 1)
    }

    // MARK: - Spend control

    @Test("a member's monthly cap decodes from the string amounts the backend sends")
    func spendControlStringAmounts() {
        let usage = CodexFixtures.decode(CodexFixtures.enterpriseSpendControlJSON)
        let limit = usage.spendControl?.individualLimit

        #expect(usage.spendControl?.reached == false)
        #expect(limit?.source == "workspace_default")
        #expect(limit?.limit == 25_000)
        #expect(limit?.used == 8_000)
        #expect(limit?.remaining == 17_000)
        #expect(limit?.usedPercent == 32)
        #expect(limit?.remainingPercent == 68)
        #expect(limit?.resetAfterSeconds == 86_400)
        #expect(limit?.resetDate == Date(timeIntervalSince1970: 1_778_137_680))
        // The rest of the payload is unaffected by the new block.
        #expect(usage.rateLimit?.windows.count == 1)
    }

    @Test("the cap also decodes when amounts arrive as numbers and percentages as strings")
    func spendControlSwappedShapes() {
        let usage = CodexFixtures.decode("""
        { "spend_control": { "reached": true, "individual_limit": {
            "limit": 25000, "used": 25000.5, "remaining": 0,
            "used_percent": "100", "remaining_percent": "0", "reset_at": "1778137680" } } }
        """)
        let limit = usage.spendControl?.individualLimit

        #expect(usage.spendControl?.reached == true)
        #expect(limit?.limit == 25_000)
        #expect(limit?.used == 25_000.5)
        #expect(limit?.usedPercent == 100)
        #expect(limit?.resetAt == 1_778_137_680)
        #expect(limit?.source == nil)
    }

    @Test("a bare scalar cap, as an earlier codex.json stored it, still reads as the cap")
    func spendControlLegacyScalar() {
        let number = CodexFixtures.decode("""
        { "spend_control": { "reached": false, "individual_limit": 500 } }
        """)
        #expect(number.spendControl?.individualLimit == CodexSpendLimit(limit: 500))

        let string = CodexFixtures.decode("""
        { "spend_control": { "reached": false, "individual_limit": "500" } }
        """)
        #expect(string.spendControl?.individualLimit?.limit == 500)
    }

    @Test("an absent, null or empty cap degrades to nil without losing the reached flag")
    func spendControlMissingCap() {
        #expect(CodexFixtures.decode(CodexFixtures.plusJSON).spendControl?.individualLimit == nil)

        let empty = CodexFixtures.decode("""
        { "spend_control": { "reached": true, "individual_limit": { "source": "x", "limit": "n/a" } } }
        """)
        #expect(empty.spendControl?.reached == true)
        #expect(empty.spendControl?.individualLimit == nil)
    }

    @Test("an out-of-range reset time is dropped rather than trapping")
    func spendControlOversizedReset() {
        let usage = CodexFixtures.decode("""
        { "spend_control": { "individual_limit": { "limit": "10", "reset_at": 1e300, "reset_after_seconds": "nan" } } }
        """)
        #expect(usage.spendControl?.individualLimit?.limit == 10)
        #expect(usage.spendControl?.individualLimit?.resetAt == nil)
        #expect(usage.spendControl?.individualLimit?.resetAfterSeconds == nil)
    }

    // MARK: - Round trip

    @Test("re-decoding what we encode preserves every field the widget renders")
    func roundTrip() throws {
        let original = CodexFixtures.decode(CodexFixtures.plusJSON)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("the monthly cap survives the codex.json round trip")
    func spendControlRoundTrip() throws {
        let original = CodexFixtures.decode(CodexFixtures.enterpriseSpendControlJSON)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: encoded)

        #expect(decoded.spendControl == original.spendControl)
        #expect(decoded.spendControl?.individualLimit?.limit == 25_000)
    }

    @Test("identity fields are never carried into the persisted payload")
    func identityIsNotPersisted() throws {
        let original = CodexFixtures.decode(CodexFixtures.proliteJSON)
        let encoded = try JSONEncoder().encode(original)
        let json = String(decoding: encoded, as: UTF8.self)

        #expect(!json.contains("redacted@example.com"))
        #expect(!json.contains("user-redacted"))
        #expect(!json.contains("00000000-0000-0000-0000-000000000000"))
    }

    // MARK: - Derived state

    @Test("limit reached is taken from the server verdict, not the percentage")
    func limitReachedComesFromServer() {
        #expect(CodexFixtures.decode(CodexFixtures.limitReachedJSON).isLimitReached)
        #expect(!CodexFixtures.decode(CodexFixtures.plusJSON).isLimitReached)

        // 100% but explicitly still allowed: trust the server.
        let allowedAtFull = CodexFixtures.usage(
            primary: CodexFixtures.window(usedPercent: 100, windowSeconds: 18_000, resetAt: Date()),
            limitReached: false
        )
        #expect(!allowedAtFull.isLimitReached)
    }

    @Test("epoch seconds become a reset date")
    func resetDateConversion() {
        let usage = CodexFixtures.decode(CodexFixtures.proliteJSON)
        #expect(usage.rateLimit?.primaryWindow?.resetDate == Date(timeIntervalSince1970: 1_789_457_646))
    }

    @Test("a zero or missing reset_at yields no date rather than 1970")
    func missingResetAt() {
        let usage = CodexFixtures.decode("""
        { "rate_limit": { "primary_window": { "used_percent": 5, "limit_window_seconds": 18000 } } }
        """)
        #expect(usage.rateLimit?.primaryWindow?.resetDate == nil)
        #expect(usage.rateLimit?.primaryWindow?.usedPercent == 5)
    }
}

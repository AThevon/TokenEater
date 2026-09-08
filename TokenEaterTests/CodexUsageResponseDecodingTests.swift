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

    // MARK: - Round trip

    @Test("re-decoding what we encode preserves every field the widget renders")
    func roundTrip() throws {
        let original = CodexFixtures.decode(CodexFixtures.plusJSON)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: encoded)

        #expect(decoded == original)
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

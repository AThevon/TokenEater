import Testing
import Foundation

@Suite("RateLimitBackoff")
struct RateLimitBackoffTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Exponential backoff on absent / zero Retry-After

    @Test("first 429 with no server hint backs off 30 min")
    func firstRateLimitUsesThirtyMinutes() {
        let r = RateLimitBackoff.nextRetryDate(consecutiveRateLimits: 0, serverRetryAfter: nil, now: now)
        #expect(r.consecutiveRateLimits == 1)
        #expect(r.date.timeIntervalSince(now) == 30 * 60)
    }

    @Test("consecutive 429s climb the exponential ladder and cap at 6h")
    func consecutiveRateLimitsClimbAndCap() {
        let expected: [TimeInterval] = [30 * 60, 60 * 60, 2 * 3600, 4 * 3600, 6 * 3600, 6 * 3600]
        var consecutive = 0
        for step in expected {
            let r = RateLimitBackoff.nextRetryDate(consecutiveRateLimits: consecutive, serverRetryAfter: nil, now: now)
            #expect(r.date.timeIntervalSince(now) == step)
            consecutive = r.consecutiveRateLimits
        }
    }

    @Test("retry-after of 0 is treated as no hint (exponential)")
    func zeroRetryAfterFallsBackToExponential() {
        let r = RateLimitBackoff.nextRetryDate(consecutiveRateLimits: 0, serverRetryAfter: 0, now: now)
        #expect(r.consecutiveRateLimits == 1)
        #expect(r.date.timeIntervalSince(now) == 30 * 60)
    }

    // MARK: - Honour a real positive Retry-After

    @Test("positive server Retry-After is honoured and does not bump the counter")
    func positiveRetryAfterHonoured() {
        let r = RateLimitBackoff.nextRetryDate(consecutiveRateLimits: 2, serverRetryAfter: 45, now: now)
        #expect(r.date.timeIntervalSince(now) == 45)
        #expect(r.consecutiveRateLimits == 2)
    }

    // MARK: - effectiveInterval mapping

    @Test("effectiveInterval mirrors the per-speed clamping")
    func effectiveIntervalClamps() {
        #expect(RateLimitBackoff.effectiveInterval(speed: .fast, baseInterval: 300) == 120)
        #expect(RateLimitBackoff.effectiveInterval(speed: .fast, baseInterval: 90) == 90)
        #expect(RateLimitBackoff.effectiveInterval(speed: .normal, baseInterval: 300) == 300)
        #expect(RateLimitBackoff.effectiveInterval(speed: .slow, baseInterval: 300) == 1200)
        #expect(RateLimitBackoff.effectiveInterval(speed: .slow, baseInterval: 700) == 1400)
    }
}

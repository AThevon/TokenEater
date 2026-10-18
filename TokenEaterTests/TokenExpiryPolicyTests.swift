import Testing
import Foundation

@Suite("TokenExpiryPolicy")
struct TokenExpiryPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - isExpired

    @Test("an unknown expiry never counts as expired")
    func unknownExpiryIsNotExpired() {
        #expect(TokenExpiryPolicy.isExpired(nil, now: now) == false)
    }

    @Test("a past expiry is expired")
    func pastExpiryIsExpired() {
        #expect(TokenExpiryPolicy.isExpired(now.addingTimeInterval(-1), now: now))
    }

    @Test("an expiry inside the margin is treated as expired")
    func expiryInsideMarginIsExpired() {
        #expect(TokenExpiryPolicy.isExpired(now.addingTimeInterval(30), now: now))
    }

    @Test("an expiry beyond the margin is valid")
    func expiryBeyondMarginIsValid() {
        #expect(TokenExpiryPolicy.isExpired(now.addingTimeInterval(120), now: now) == false)
    }

    // MARK: - staleSince (escalation threshold)

    /// The first hour is the routine lag before Claude Code's next run, so
    /// the app keeps its calm "waiting" state.
    @Test("a login expired under an hour ago does not escalate")
    func recentExpiryStaysCalm() {
        let expiry = now.addingTimeInterval(-45 * 60)
        #expect(TokenExpiryPolicy.staleSince(expiresAt: expiry, now: now) == nil)
    }

    @Test("exactly one hour is still the calm side of the threshold")
    func exactlyOneHourStaysCalm() {
        let expiry = now.addingTimeInterval(-3600)
        #expect(TokenExpiryPolicy.staleSince(expiresAt: expiry, now: now) == nil)
    }

    @Test("a login expired over an hour ago escalates and reports its expiry")
    func oldExpiryEscalates() {
        let expiry = now.addingTimeInterval(-3601)
        #expect(TokenExpiryPolicy.staleSince(expiresAt: expiry, now: now) == expiry)
    }

    @Test("a valid or unknown login never escalates")
    func validOrUnknownNeverEscalates() {
        #expect(TokenExpiryPolicy.staleSince(expiresAt: now.addingTimeInterval(3600), now: now) == nil)
        #expect(TokenExpiryPolicy.staleSince(expiresAt: nil, now: now) == nil)
    }
}

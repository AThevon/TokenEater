import Testing
import Foundation

/// Tests for the pure JSON-extraction half of `SecurityCLIReader`. The
/// `Process` spawn that calls `/usr/bin/security` is integration territory
/// (the binary, the Keychain ACL, and the actual OAuth item must all line
/// up); the JSON parser is exercised here in isolation.
@Suite("SecurityCLIReader.extractToken")
struct SecurityCLIReaderTests {

    @Test("Valid Claude Code OAuth blob -> accessToken")
    func validBlob() {
        let raw = """
        {
          "claudeAiOauth": {
            "accessToken": "mock-access-token-for-tests-only",
            "refreshToken": "mock-refresh-token-for-tests-only",
            "expiresAt": 1735689600
          }
        }
        """
        let token = SecurityCLIReader.extractToken(fromKeychainPassword: raw)
        #expect(token == "mock-access-token-for-tests-only")
    }

    @Test("Trims surrounding whitespace before parsing")
    func trimsWhitespace() {
        // The reader pre-trims, so `extractToken` shouldn't have to. Still
        // verify the contract: leading/trailing junk-free input parses.
        let raw = #"{"claudeAiOauth":{"accessToken":"trimmed"}}"#
        let token = SecurityCLIReader.extractToken(fromKeychainPassword: raw)
        #expect(token == "trimmed")
    }

    @Test("Empty payload returns nil")
    func empty() {
        #expect(SecurityCLIReader.extractToken(fromKeychainPassword: "") == nil)
    }

    @Test("Plain string (not JSON) returns nil")
    func plainString() {
        #expect(SecurityCLIReader.extractToken(fromKeychainPassword: "just-a-token") == nil)
    }

    @Test("JSON without claudeAiOauth wrapper returns nil")
    func missingWrapper() {
        let raw = #"{"accessToken":"top-level-not-supported"}"#
        #expect(SecurityCLIReader.extractToken(fromKeychainPassword: raw) == nil)
    }

    @Test("claudeAiOauth without accessToken returns nil")
    func wrapperWithoutAccessToken() {
        let raw = #"{"claudeAiOauth":{"refreshToken":"rfh-only"}}"#
        #expect(SecurityCLIReader.extractToken(fromKeychainPassword: raw) == nil)
    }

    @Test("Empty accessToken value returns nil")
    func emptyAccessToken() {
        let raw = #"{"claudeAiOauth":{"accessToken":""}}"#
        #expect(SecurityCLIReader.extractToken(fromKeychainPassword: raw) == nil)
    }

    @Test("Wrong type for accessToken returns nil")
    func wrongAccessTokenType() {
        let raw = #"{"claudeAiOauth":{"accessToken":42}}"#
        #expect(SecurityCLIReader.extractToken(fromKeychainPassword: raw) == nil)
    }

    @Test("Malformed JSON returns nil instead of throwing")
    func malformedJSON() {
        let raw = #"{"claudeAiOauth":{"accessToken""#
        #expect(SecurityCLIReader.extractToken(fromKeychainPassword: raw) == nil)
    }

    @Test("Extra fields beyond accessToken are ignored")
    func extraFields() {
        let raw = """
        {
          "claudeAiOauth": {
            "accessToken": "mock-access-token-multifield",
            "scopes": ["usage:read"],
            "tokenType": "Bearer",
            "metadata": {"plan": "pro"}
          },
          "extra": "ignored"
        }
        """
        #expect(SecurityCLIReader.extractToken(fromKeychainPassword: raw) == "mock-access-token-multifield")
    }

    // MARK: - Exit codes (#273)

    /// `security`'s two meaningful exit codes. They used to collapse into a
    /// bare nil, which is how a refused read became indistinguishable from a
    /// machine that simply has no such item.
    @Test("exit 44 is a missing item and 45 is a refusal")
    func exitCodesAreNamed() {
        #expect(SecurityCLIReader.failure(forExitCode: 44) == .notFound)
        #expect(SecurityCLIReader.failure(forExitCode: 45) == .accessDenied)
        #expect(SecurityCLIReader.failure(forExitCode: 1) == .unknown)
    }

    // MARK: - Shadowed service name (#268)

    private static func payload(token: String, expiresAt: Int? = nil) -> String {
        let expiry = expiresAt.map { ", \"expiresAt\": \($0)" } ?? ""
        return "{\"claudeAiOauth\": {\"accessToken\": \"\(token)\"\(expiry)}}"
    }

    /// The reported shape: a second item under the same service name holding
    /// only MCP OAuth state. A lookup by service alone can hand back that one,
    /// and it carries no login at all.
    @Test("an item with no claudeAiOauth never wins over the real login")
    func shadowingItemLoses() {
        let best = SecurityCLIReader.bestCredential(among: [
            (account: "unknown", raw: #"{"mcpOAuth": {"some": "state"}}"#),
            (account: "athevon", raw: Self.payload(token: "real-token"))
        ])

        #expect(best?.account == "athevon")
        #expect(best?.credential.token == "real-token")
    }

    @Test("with two real logins the one that lasts longest wins")
    func freshestCredentialWins() {
        let best = SecurityCLIReader.bestCredential(among: [
            (account: "old", raw: Self.payload(token: "old-token", expiresAt: 1_700_000_000_000)),
            (account: "new", raw: Self.payload(token: "new-token", expiresAt: 1_900_000_000_000))
        ])

        #expect(best?.credential.token == "new-token")
    }

    @Test("nothing usable anywhere returns nothing rather than a shadowed item")
    func noUsablePayload() {
        let best = SecurityCLIReader.bestCredential(among: [
            (account: "unknown", raw: #"{"mcpOAuth": {}}"#),
            (account: "other", raw: "not json")
        ])

        #expect(best == nil)
    }

    /// Claude Code writes the expiry in milliseconds. Reading it as seconds
    /// would put every token in 1970 and make the freshest-wins rule a coin
    /// toss.
    @Test("a millisecond expiry is read as milliseconds")
    func millisecondExpiry() {
        let credential = SecurityCLIReader.credential(
            fromKeychainPassword: Self.payload(token: "t", expiresAt: 1_900_000_000_000)
        )

        #expect(credential?.expiresAt == Date(timeIntervalSince1970: 1_900_000_000))
    }

}

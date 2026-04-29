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
}

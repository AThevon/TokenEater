import Testing
import Foundation

@Suite("JWTClaims")
struct JWTClaimsTests {

    @Test("reads the OpenAI auth claims Codex tokens carry")
    func readsClaims() {
        let expiry = Date(timeIntervalSince1970: 1_789_296_665)
        let token = CodexFixtures.jwt(planType: "prolite", accountId: "acct-42", exp: expiry)

        #expect(JWTClaims.chatGPTPlanType(of: token) == "prolite")
        #expect(JWTClaims.chatGPTAccountID(of: token) == "acct-42")
        #expect(JWTClaims.expiration(of: token) == expiry)
    }

    @Test("reads iat when present")
    func readsIssuedAt() {
        let issued = Date(timeIntervalSince1970: 1_788_432_665)
        let token = CodexFixtures.jwt(exp: nil, iat: issued)

        #expect(JWTClaims.issuedAt(of: token) == issued)
    }

    @Test("handles base64url payloads that need padding")
    func paddingVariants() {
        // Exercises payload lengths hitting each of the three padding cases.
        for accountId in ["a", "ab", "abc", "abcd"] {
            let token = CodexFixtures.jwt(accountId: accountId)
            #expect(JWTClaims.chatGPTAccountID(of: token) == accountId)
        }
    }

    @Test("malformed input yields nil rather than throwing")
    func malformedInput() {
        #expect(JWTClaims.decode("") == nil)
        #expect(JWTClaims.decode("not-a-jwt") == nil)
        #expect(JWTClaims.decode("only.two") == nil)
        #expect(JWTClaims.decode("aaa.!!!not-base64!!!.ccc") == nil)
        #expect(JWTClaims.expiration(of: "garbage") == nil)
        #expect(JWTClaims.chatGPTPlanType(of: "garbage") == nil)
    }

    @Test("a token without the OpenAI namespace yields nil claims, not a crash")
    func missingNamespace() {
        let payload = Data(#"{"sub":"someone"}"#.utf8)
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(encoded).sig"

        #expect(JWTClaims.decode(token)?["sub"] as? String == "someone")
        #expect(JWTClaims.chatGPTPlanType(of: token) == nil)
    }
}

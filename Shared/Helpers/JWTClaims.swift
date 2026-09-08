import Foundation

/// Reads the payload of a JWT without verifying its signature.
///
/// Verification would be pointless here: we are the token's bearer, not its
/// audience, and the claims are used only for display (plan badge) and for
/// skipping a request we know would 401. The signature is checked by the server
/// that actually accepts the token.
enum JWTClaims {

    // MARK: - Type Methods

    /// Decodes the payload segment into a dictionary. Returns nil for anything
    /// that is not a three-segment token with a base64url JSON payload.
    static func decode(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        guard let data = base64URLDecode(String(segments[1])) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// `exp` as a Date.
    static func expiration(of token: String) -> Date? {
        guard let claims = decode(token), let exp = claims["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    /// `iat` as a Date.
    static func issuedAt(of token: String) -> Date? {
        guard let claims = decode(token), let iat = claims["iat"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: iat)
    }

    /// `chatgpt_plan_type` from the OpenAI auth claim namespace. Present on both
    /// the id token and the access token Codex stores.
    static func chatGPTPlanType(of token: String) -> String? {
        openAIAuthClaims(of: token)?["chatgpt_plan_type"] as? String
    }

    /// `chatgpt_account_id` from the same namespace, used when `auth.json` has
    /// no top-level `account_id`.
    static func chatGPTAccountID(of token: String) -> String? {
        openAIAuthClaims(of: token)?["chatgpt_account_id"] as? String
    }

    // MARK: - Private Methods

    private static func openAIAuthClaims(of token: String) -> [String: Any]? {
        decode(token)?["https://api.openai.com/auth"] as? [String: Any]
    }

    /// base64url -> Data. JWT segments drop the padding and swap two alphabet
    /// characters, both of which `Data(base64Encoded:)` rejects.
    private static func base64URLDecode(_ segment: String) -> Data? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}

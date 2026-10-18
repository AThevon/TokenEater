import Foundation

/// One Claude Code login, as Claude Code stores it. The Keychain item and
/// `~/.claude/.credentials.json` hold the same `claudeAiOauth` JSON, so both
/// readers parse it here and both report the expiry, which is what lets
/// `TokenProvider` tell a live login from a dead one (#268).
struct ClaudeCredential: Equatable, Sendable {
    let token: String
    /// When the access token stops working. Claude Code refreshes it when
    /// it runs; TokenEater only reads it, so this is the honest answer to
    /// "why did the API say no" rather than a thing it can act on.
    let expiresAt: Date?

    /// Pulls `claudeAiOauth.accessToken` and its expiry out of the payload.
    /// Nil if the payload isn't JSON, doesn't carry the expected nested keys,
    /// or the access token field is empty.
    static func parse(_ data: Data) -> ClaudeCredential? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        return ClaudeCredential(token: token, expiresAt: expiry(from: oauth["expiresAt"]))
    }

    /// Claude Code writes `expiresAt` in milliseconds. Seconds are accepted
    /// too rather than guessed at: a value small enough to be seconds is
    /// read as seconds, so a format change does not silently land the expiry
    /// in 1970.
    static func expiry(from value: Any?) -> Date? {
        let raw: Double
        switch value {
        case let number as Double: raw = number
        case let number as Int: raw = Double(number)
        case let string as String: guard let parsed = Double(string) else { return nil }; raw = parsed
        default: return nil
        }
        guard raw > 0 else { return nil }
        let seconds = raw > 1_000_000_000_000 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }
}

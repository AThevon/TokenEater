import Foundation

/// The subset of `~/.codex/auth.json` TokenEater needs.
///
/// Read-only by design: Codex refresh tokens are single-use, so a refresh
/// performed here would invalidate the one the CLI keeps on disk. The refresh
/// token is therefore never even parsed.
struct CodexCredentials: Equatable, Sendable {
    let accessToken: String
    let accountId: String?
    /// Raw `auth_mode` from the file (`chatgpt`, `apikey`, ...). nil in older
    /// files that predate the key.
    let authMode: String?
    /// `iat` of the access token, mirrored by Codex into `last_refresh`.
    let lastRefresh: Date?
    /// `exp` of the access token. ~10 days out in practice.
    let expiresAt: Date?
    /// `chatgpt_plan_type` claim, so the plan badge survives an offline start.
    let planType: String?

    /// Auth modes that carry ChatGPT rate-limit windows. API keys are billed
    /// per token with no rolling window, so there is nothing for us to track.
    static let trackableAuthModes: Set<String> = ["chatgpt", "chatgptauthtokens"]

    /// Auth modes that bill per token instead of per window. Used to explain
    /// why there is nothing to track, as opposed to nothing being there.
    static let apiKeyAuthModes: Set<String> = ["apikey", "bedrockapikey", "bedrockaccesskeys"]

    var isAPIKeyMode: Bool {
        guard let authMode else { return false }
        return Self.apiKeyAuthModes.contains(authMode.lowercased())
    }

    var isTrackable: Bool {
        guard !accessToken.isEmpty else { return false }
        // A missing auth_mode alongside real tokens means an older file written
        // before the key existed; those were always ChatGPT logins.
        guard let authMode else { return true }
        return Self.trackableAuthModes.contains(authMode.lowercased())
    }

    func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

import Foundation

/// What TokenEater found when it looked for Codex credentials. Drives the
/// Providers card copy and the auto-enable decision; never surfaces a token.
enum CodexAuthState: Equatable {

    // MARK: - Enumeration Cases

    /// No `~/.codex` directory: the CLI was never installed for this user.
    case notInstalled
    /// The directory exists but holds no usable credentials: logged out, or a
    /// build storing them in the Keychain instead of `auth.json`.
    case noCredentials
    /// Signed in with an API key. Pay-as-you-go billing has no rolling windows,
    /// so there is nothing to track.
    case apiKeyOnly
    /// Signed in with a ChatGPT account. The only state that yields usage data.
    case chatgpt(accountId: String?, planType: String?, expiresAt: Date?)

    // MARK: - Public Properties

    var isTrackable: Bool {
        if case .chatgpt = self { return true }
        return false
    }

    var isInstalled: Bool { self != .notInstalled }

    var planType: CodexPlanType {
        guard case .chatgpt(_, let plan, _) = self else { return .unknown }
        return CodexPlanType(rawPlan: plan)
    }

    func isExpired(now: Date = Date()) -> Bool {
        guard case .chatgpt(_, _, let expiresAt) = self, let expiresAt else { return false }
        return expiresAt <= now
    }
}

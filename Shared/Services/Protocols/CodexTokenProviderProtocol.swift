import Foundation

protocol CodexTokenProviderProtocol: Sendable {
    /// Cached credentials; re-reads `auth.json` only when the cache is empty.
    func currentCredentials() -> CodexCredentials?
    /// Drops the cache so the next read picks up a token Codex just refreshed.
    /// Call after a 401.
    func invalidate()
    /// Re-reads from disk, bypassing the cache. True when the access token
    /// changed, i.e. Codex refreshed it or the user logged into another account.
    func refreshIfChanged() -> Bool
    /// Current auth state, read fresh (cheap: one small file).
    var authState: CodexAuthState { get }
    /// Resolved Codex home, for the file watcher and diagnostics.
    var codexHomeURL: URL { get }
    var authFileURL: URL { get }
}

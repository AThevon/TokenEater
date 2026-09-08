import Foundation

protocol CodexAuthReaderProtocol: Sendable {
    /// Path of the resolved `auth.json`, for diagnostics.
    var authFileURL: URL { get }
    /// Resolved Codex home (`CODEX_HOME` or `~/.codex`), for the file watcher.
    var codexHomeURL: URL { get }
    /// Trackable ChatGPT credentials, or nil for every other state (no file,
    /// API-key mode, unreadable JSON).
    func readCredentials() -> CodexCredentials?
    /// Coarse state for the UI, including the states `readCredentials` maps to nil.
    func authState() -> CodexAuthState
}

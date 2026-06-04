import Foundation

protocol TokenProviderProtocol: Sendable {
    func currentToken() -> String?
    /// Whether a token source exists (config.json or credentials file), even if not yet decryptable
    func hasTokenSource() -> Bool
    /// Clear cached token - call after 401 so next read re-checks Keychain
    func invalidateToken()
    /// Re-reads the token from its sources (Keychain/files), bypassing the
    /// in-memory cache, and updates the cache. Returns true when the token
    /// changed since the last read - i.e. an account swap (`cswap`, `claude
    /// /login`) or token rotation that the file watcher cannot observe because
    /// the active token lives in the Keychain, not in a watched file.
    func refreshTokenIfChanged() -> Bool
    var isBootstrapped: Bool { get }
    func bootstrap() throws
}

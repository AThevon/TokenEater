import Foundation

protocol TokenProviderProtocol: Sendable {
    func currentToken() -> String?
    /// Whether a token source exists (config.json or credentials file), even if not yet decryptable
    func hasTokenSource() -> Bool
    /// Clear cached token - call after 401 so next read re-checks Keychain
    func invalidateToken()
    var isBootstrapped: Bool { get }
    func bootstrap() throws
}

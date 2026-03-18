import Foundation

protocol TokenProviderProtocol: Sendable {
    func currentToken() -> String?
    /// Whether a token source exists (config.json or credentials file), even if not yet decryptable
    func hasTokenSource() -> Bool
    var isBootstrapped: Bool { get }
    func bootstrap() throws
}

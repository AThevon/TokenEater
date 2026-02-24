import Foundation

protocol KeychainServiceProtocol: Sendable {
    /// Interactive read — may trigger macOS Keychain dialog.
    func readOAuthToken() -> String?
    /// Silent read — never triggers dialog. Returns nil if auth is needed.
    func readOAuthTokenSilently() -> String?
    func tokenExists() -> Bool
}

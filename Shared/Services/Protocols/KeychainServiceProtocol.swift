import Foundation

protocol KeychainServiceProtocol: Sendable {
    /// Read OAuth token from ~/.claude/.credentials.json.
    func readToken() -> String?
    /// Check if credentials file or Keychain has a token (silent, no popup).
    func tokenExists() -> Bool
    /// Silent Keychain read — for boot/onboarding only. Never triggers a dialog.
    func readKeychainTokenSilently() -> String?
}

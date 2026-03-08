import Foundation

protocol KeychainServiceProtocol: Sendable {
    /// Read OAuth token from ~/.claude/.credentials.json.
    func readToken() -> String?
    /// Check if the credentials file exists.
    func tokenExists() -> Bool
}

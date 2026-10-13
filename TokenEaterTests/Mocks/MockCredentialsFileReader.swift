import Foundation

final class MockCredentialsFileReader: CredentialsFileReaderProtocol, @unchecked Sendable {
    var storedToken: String?
    /// Expiry of `storedToken`. Nil reproduces a file that carries none.
    var storedExpiresAt: Date?
    var fileExists: Bool = false

    func readCredential() -> ClaudeCredential? {
        storedToken.map { ClaudeCredential(token: $0, expiresAt: storedExpiresAt) }
    }
    func tokenExists() -> Bool { fileExists }
}

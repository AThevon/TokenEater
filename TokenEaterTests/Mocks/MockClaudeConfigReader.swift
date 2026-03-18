import Foundation

final class MockClaudeConfigReader: ClaudeConfigReaderProtocol, @unchecked Sendable {
    var encryptedToken: String?

    func readEncryptedToken() -> String? {
        encryptedToken
    }
}

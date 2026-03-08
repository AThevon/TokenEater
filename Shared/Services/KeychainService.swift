import Foundation

/// Reads OAuth tokens from the Claude Code credentials file (~/.claude/.credentials.json).
/// Historical note: this used to also read from macOS Keychain, but credentials file
/// is always up-to-date and avoids Keychain popup dialogs after sleep.
final class KeychainService: KeychainServiceProtocol, @unchecked Sendable {

    private let credentialsFileReader: CredentialsFileReaderProtocol

    init(credentialsFileReader: CredentialsFileReaderProtocol = CredentialsFileReader()) {
        self.credentialsFileReader = credentialsFileReader
    }

    func readToken() -> String? {
        credentialsFileReader.readToken()
    }

    func tokenExists() -> Bool {
        credentialsFileReader.tokenExists()
    }
}

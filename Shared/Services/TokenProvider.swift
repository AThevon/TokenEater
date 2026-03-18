import Foundation

final class TokenProvider: TokenProviderProtocol, @unchecked Sendable {
    private let credentialsFileReader: CredentialsFileReaderProtocol
    private let configReader: ClaudeConfigReaderProtocol
    private let decryptionService: ElectronDecryptionServiceProtocol

    init(
        credentialsFileReader: CredentialsFileReaderProtocol = CredentialsFileReader(),
        configReader: ClaudeConfigReaderProtocol = ClaudeConfigReader(),
        decryptionService: ElectronDecryptionServiceProtocol = ElectronDecryptionService()
    ) {
        self.credentialsFileReader = credentialsFileReader
        self.configReader = configReader
        self.decryptionService = decryptionService
    }

    var isBootstrapped: Bool { decryptionService.hasEncryptionKey }

    func hasTokenSource() -> Bool {
        // Check if credentials file has a token (no Keychain needed)
        if credentialsFileReader.readToken() != nil { return true }
        // Check if config.json has an encrypted token (doesn't need decryption key yet)
        if configReader.readEncryptedToken() != nil { return true }
        return false
    }

    func currentToken() -> String? {
        // Source 1: credentials file (future-proof for macOS)
        if let token = credentialsFileReader.readToken() { return token }

        // Source 2: decrypt config.json
        if decryptionService.hasEncryptionKey,
           let encrypted = configReader.readEncryptedToken(),
           let data = try? decryptionService.decrypt(encrypted),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String,
           !token.isEmpty {
            return token
        }

        return nil
    }

    func bootstrap() throws {
        try decryptionService.bootstrapEncryptionKey()
    }
}

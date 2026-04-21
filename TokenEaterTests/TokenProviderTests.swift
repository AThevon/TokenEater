import Testing
import Foundation

@Suite("TokenProvider")
struct TokenProviderTests {

    // MARK: - Helpers

    /// keychainReader that always returns nil (no Keychain in tests)
    private static let noKeychain: TokenProvider.KeychainTokenReader = { _ in nil }

    private func makeSUT(
        securityCLIToken: String? = nil,
        credentialsToken: String? = nil,
        keychainToken: String? = nil,
        encryptedToken: String? = nil,
        hasEncryptionKey: Bool = false,
        decryptedData: Data? = nil
    ) -> (TokenProvider, MockSecurityCLIReader, MockCredentialsFileReader, MockClaudeConfigReader, MockElectronDecryptionService) {
        let securityCLI = MockSecurityCLIReader()
        securityCLI.token = securityCLIToken

        let credentials = MockCredentialsFileReader()
        credentials.storedToken = credentialsToken

        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = encryptedToken

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = hasEncryptionKey
        decryption.decryptedData = decryptedData

        let keychainReader: TokenProvider.KeychainTokenReader = { _ in keychainToken }

        let provider = TokenProvider(
            securityCLIReader: securityCLI,
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption,
            keychainReader: keychainReader
        )

        return (provider, securityCLI, credentials, configReader, decryption)
    }

    // MARK: - Tests

    @Test("security CLI is the primary source")
    func securityCLIFirst() {
        let (provider, securityCLI, _, _, decryption) = makeSUT(
            securityCLIToken: "security-token",
            credentialsToken: "creds-token",
            keychainToken: "keychain-token",
            encryptedToken: "some-encrypted",
            hasEncryptionKey: true
        )

        let token = provider.currentToken()

        #expect(token == "security-token")
        #expect(securityCLI.readCallCount == 1)
        #expect(decryption.decryptCallCount == 0)
    }

    @Test("falls back to credentials file when security CLI returns nil")
    func fallbackToCredentialsFile() {
        let (provider, _, _, _, decryption) = makeSUT(
            securityCLIToken: nil,
            credentialsToken: "creds-token",
            keychainToken: "keychain-token"
        )

        let token = provider.currentToken()

        #expect(token == "creds-token")
        #expect(decryption.decryptCallCount == 0)
    }

    @Test("falls back to keychain when security CLI and credentials file miss")
    func fallbackToKeychain() {
        let (provider, _, _, _, decryption) = makeSUT(
            securityCLIToken: nil,
            credentialsToken: nil,
            keychainToken: "keychain-token"
        )

        let token = provider.currentToken()

        #expect(token == "keychain-token")
        #expect(decryption.decryptCallCount == 0)
    }

    @Test("falls back to config.json decryption when earlier sources miss")
    func fallbackToConfigDecryption() {
        let oauthJSON: [String: Any] = [
            "claudeAiOauth": ["accessToken": "decrypted-token"]
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: oauthJSON)

        let (provider, _, _, _, decryption) = makeSUT(
            securityCLIToken: nil,
            credentialsToken: nil,
            keychainToken: nil,
            encryptedToken: "encrypted-blob",
            hasEncryptionKey: true,
            decryptedData: jsonData
        )

        let token = provider.currentToken()

        #expect(token == "decrypted-token")
        #expect(decryption.decryptCallCount == 1)
    }

    @Test("extracts token from UUID-based config.json format")
    func extractsUUIDFormat() {
        let uuidJSON: [String: Any] = [
            "uuid:uuid:https://api.anthropic.com": ["token": "sk-ant-oat01-test123"]
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: uuidJSON)

        let (provider, _, _, _, _) = makeSUT(
            securityCLIToken: nil,
            credentialsToken: nil,
            keychainToken: nil,
            encryptedToken: "encrypted-blob",
            hasEncryptionKey: true,
            decryptedData: jsonData
        )

        #expect(provider.currentToken() == "sk-ant-oat01-test123")
    }

    @Test("returns nil when no source available")
    func returnsNilWhenNoSource() {
        let (provider, _, _, _, _) = makeSUT()

        #expect(provider.currentToken() == nil)
    }

    @Test("isBootstrapped is always true")
    func isBootstrappedAlwaysTrue() {
        let (provider, _, _, _, _) = makeSUT(hasEncryptionKey: false)
        #expect(provider.isBootstrapped == true)
    }

    @Test("hasTokenSource returns true when security CLI has token")
    func hasTokenSourceViaSecurityCLI() {
        let (provider, _, _, _, _) = makeSUT(securityCLIToken: "some-token")
        #expect(provider.hasTokenSource() == true)
    }

    @Test("hasTokenSource returns true when keychain has token")
    func hasTokenSourceViaKeychain() {
        let (provider, _, _, _, _) = makeSUT(keychainToken: "some-token")
        #expect(provider.hasTokenSource() == true)
    }

    @Test("hasTokenSource returns false when nothing available")
    func hasTokenSourceReturnsFalse() {
        let (provider, _, _, _, _) = makeSUT()
        #expect(provider.hasTokenSource() == false)
    }

    @Test("config.json decryption is tried before direct Keychain")
    func configJsonBeforeKeychain() {
        let oauthJSON: [String: Any] = [
            "claudeAiOauth": ["accessToken": "config-token"]
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: oauthJSON)

        var keychainWasCalled = false
        let securityCLI = MockSecurityCLIReader()
        let credentials = MockCredentialsFileReader()
        credentials.storedToken = nil

        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = "encrypted-blob"

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = true
        decryption.decryptedData = jsonData

        let keychainReader: TokenProvider.KeychainTokenReader = { _ in
            keychainWasCalled = true
            return "keychain-token"
        }

        let provider = TokenProvider(
            securityCLIReader: securityCLI,
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption,
            keychainReader: keychainReader
        )

        let token = provider.currentToken()

        #expect(token == "config-token")
        #expect(keychainWasCalled == false)
    }

    @Test("silent re-bootstrap recovers when decryption key is stale")
    func silentRebootstrapRecovery() {
        let oauthJSON: [String: Any] = [
            "claudeAiOauth": ["accessToken": "recovered-token"]
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: oauthJSON)

        let securityCLI = MockSecurityCLIReader()
        let credentials = MockCredentialsFileReader()
        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = "encrypted-blob"

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = false // key not loaded initially
        decryption.silentRebootstrapResult = true // but silent re-bootstrap works
        decryption.decryptedData = jsonData

        let provider = TokenProvider(
            securityCLIReader: securityCLI,
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption,
            keychainReader: { _ in nil }
        )

        let token = provider.currentToken()

        #expect(token == "recovered-token")
        #expect(decryption.silentRebootstrapCallCount == 1)
        #expect(decryption.decryptCallCount == 1)
    }

    @Test("falls back to Keychain when config.json unavailable and re-bootstrap fails")
    func fallbackToKeychainWhenConfigUnavailable() {
        let securityCLI = MockSecurityCLIReader()
        let credentials = MockCredentialsFileReader()
        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = nil // no config.json

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = false

        let provider = TokenProvider(
            securityCLIReader: securityCLI,
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption,
            keychainReader: { _ in "keychain-fallback" }
        )

        let token = provider.currentToken()

        #expect(token == "keychain-fallback")
    }
}

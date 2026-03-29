import Testing
import Foundation

@Suite("TokenProvider")
struct TokenProviderTests {

    // MARK: - Helpers

    /// keychainReader that always returns nil (no Keychain in tests)
    private static let noKeychain: TokenProvider.KeychainTokenReader = { _ in nil }

    private func makeSUT(
        credentialsToken: String? = nil,
        keychainToken: String? = nil,
        encryptedToken: String? = nil,
        hasEncryptionKey: Bool = false,
        decryptedData: Data? = nil
    ) -> (TokenProvider, MockCredentialsFileReader, MockClaudeConfigReader, MockElectronDecryptionService) {
        let credentials = MockCredentialsFileReader()
        credentials.storedToken = credentialsToken

        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = encryptedToken

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = hasEncryptionKey
        decryption.decryptedData = decryptedData

        let keychainReader: TokenProvider.KeychainTokenReader = { _ in keychainToken }

        let provider = TokenProvider(
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption,
            keychainReader: keychainReader
        )

        return (provider, credentials, configReader, decryption)
    }

    // MARK: - Tests

    @Test("credentials file is tried first, keychain and decryption not called")
    func credentialsFileFirst() {
        let (provider, _, _, decryption) = makeSUT(
            credentialsToken: "creds-token",
            keychainToken: "keychain-token",
            encryptedToken: "some-encrypted",
            hasEncryptionKey: true
        )

        let token = provider.currentToken()

        #expect(token == "creds-token")
        #expect(decryption.decryptCallCount == 0)
    }

    @Test("falls back to keychain when credentials file missing")
    func fallbackToKeychain() {
        let (provider, _, _, decryption) = makeSUT(
            credentialsToken: nil,
            keychainToken: "keychain-token"
        )

        let token = provider.currentToken()

        #expect(token == "keychain-token")
        #expect(decryption.decryptCallCount == 0)
    }

    @Test("falls back to config.json decryption when credentials file and keychain missing")
    func fallbackToConfigDecryption() {
        let oauthJSON: [String: Any] = [
            "claudeAiOauth": ["accessToken": "decrypted-token"]
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: oauthJSON)

        let (provider, _, _, decryption) = makeSUT(
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

        let (provider, _, _, _) = makeSUT(
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
        let (provider, _, _, _) = makeSUT()

        #expect(provider.currentToken() == nil)
    }

    @Test("isBootstrapped is always true")
    func isBootstrappedAlwaysTrue() {
        let (provider, _, _, _) = makeSUT(hasEncryptionKey: false)
        #expect(provider.isBootstrapped == true)
    }

    @Test("hasTokenSource returns true when keychain has token")
    func hasTokenSourceViaKeychain() {
        let (provider, _, _, _) = makeSUT(keychainToken: "some-token")
        #expect(provider.hasTokenSource() == true)
    }

    @Test("hasTokenSource returns false when nothing available")
    func hasTokenSourceReturnsFalse() {
        let (provider, _, _, _) = makeSUT()
        #expect(provider.hasTokenSource() == false)
    }

    @Test("config.json decryption is tried before Keychain")
    func configJsonBeforeKeychain() {
        let oauthJSON: [String: Any] = [
            "claudeAiOauth": ["accessToken": "config-token"]
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: oauthJSON)

        var keychainWasCalled = false
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

        let credentials = MockCredentialsFileReader()
        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = "encrypted-blob"

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = false // key not loaded initially
        decryption.silentRebootstrapResult = true // but silent re-bootstrap works
        decryption.decryptedData = jsonData

        let provider = TokenProvider(
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
        let credentials = MockCredentialsFileReader()
        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = nil // no config.json

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = false

        let provider = TokenProvider(
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption,
            keychainReader: { _ in "keychain-fallback" }
        )

        let token = provider.currentToken()

        #expect(token == "keychain-fallback")
    }
}

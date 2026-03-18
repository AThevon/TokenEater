import Testing
import Foundation

@Suite("TokenProvider")
struct TokenProviderTests {

    // MARK: - Helpers

    private func makeSUT(
        credentialsToken: String? = nil,
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

        let provider = TokenProvider(
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption
        )

        return (provider, credentials, configReader, decryption)
    }

    // MARK: - Tests

    @Test("credentials file is tried first, decryption not called")
    func credentialsFileFirst() {
        let (provider, _, _, decryption) = makeSUT(
            credentialsToken: "creds-token",
            encryptedToken: "some-encrypted",
            hasEncryptionKey: true
        )

        let token = provider.currentToken()

        #expect(token == "creds-token")
        #expect(decryption.decryptCallCount == 0)
    }

    @Test("falls back to config.json decryption when credentials file missing")
    func fallbackToConfigDecryption() {
        let oauthJSON: [String: Any] = [
            "claudeAiOauth": ["accessToken": "decrypted-token"]
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: oauthJSON)

        let (provider, _, _, decryption) = makeSUT(
            credentialsToken: nil,
            encryptedToken: "encrypted-blob",
            hasEncryptionKey: true,
            decryptedData: jsonData
        )

        let token = provider.currentToken()

        #expect(token == "decrypted-token")
        #expect(decryption.decryptCallCount == 1)
    }

    @Test("returns nil when no source available")
    func returnsNilWhenNoSource() {
        let (provider, _, _, _) = makeSUT()

        #expect(provider.currentToken() == nil)
    }

    @Test("isBootstrapped reflects decryption service state")
    func isBootstrappedReflectsDecryptionService() {
        let (providerNotBootstrapped, _, _, _) = makeSUT(hasEncryptionKey: false)
        #expect(providerNotBootstrapped.isBootstrapped == false)

        let (providerBootstrapped, _, _, _) = makeSUT(hasEncryptionKey: true)
        #expect(providerBootstrapped.isBootstrapped == true)
    }

    @Test("bootstrap delegates to decryption service")
    func bootstrapDelegates() throws {
        let (provider, _, _, decryption) = makeSUT()

        try provider.bootstrap()

        #expect(decryption.bootstrapCallCount == 1)
        #expect(decryption._hasEncryptionKey == true)
    }
}

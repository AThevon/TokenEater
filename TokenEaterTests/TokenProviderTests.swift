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

    // MARK: - Source diagnostic (#273)

    /// The case the bug report is made of: the live token sits in the Keychain
    /// and macOS refuses it, so the app runs on whatever the file still holds,
    /// which the API rejects. "Relaunch Claude Code" is the one piece of advice
    /// that cannot help there, so the diagnostic has to say what happened.
    @Test("a refused Keychain read plus a file token is flagged as a stale fallback")
    func refusedKeychainFallsBackAndSaysSo() {
        let (provider, securityCLI, _, _, _) = makeSUT(credentialsToken: "file-token")
        securityCLI.failure = .accessDenied

        #expect(provider.currentToken() == "file-token")
        #expect(provider.tokenDiagnostic.source == .credentialsFile)
        #expect(provider.tokenDiagnostic.keychainFailure == .accessDenied)
        #expect(provider.tokenDiagnostic.isStaleFallback)
        #expect(provider.tokenDiagnostic.authFailureHint != nil)
    }

    /// A machine that keeps its credentials in a file is not broken: the
    /// Keychain has nothing to give and the file is the real source, so no
    /// warning and the ordinary expired-token message stands.
    @Test("no Keychain item at all is not a stale fallback")
    func missingKeychainItemIsNormal() {
        let (provider, securityCLI, _, _, _) = makeSUT(credentialsToken: "file-token")
        securityCLI.failure = .notFound

        #expect(provider.currentToken() == "file-token")
        #expect(provider.tokenDiagnostic.keychainFailure == .notFound)
        #expect(provider.tokenDiagnostic.isStaleFallback == false)
        #expect(provider.tokenDiagnostic.authFailureHint == nil)
    }

    @Test("a token read from the Keychain reports the Keychain as its source")
    func keychainSourceIsReported() {
        let (provider, _, _, _, _) = makeSUT(securityCLIToken: "keychain-token", credentialsToken: "file-token")

        #expect(provider.currentToken() == "keychain-token")
        #expect(provider.tokenDiagnostic.source == .keychainCLI)
        #expect(provider.tokenDiagnostic.keychainFailure == nil)
        #expect(provider.tokenDiagnostic.isStaleFallback == false)
    }

    /// Nothing anywhere, and the Keychain timed out rather than being empty:
    /// the hint still has something to say, because the user has an action.
    @Test("a timed-out Keychain read with no token anywhere still explains itself")
    func timedOutWithNoTokenExplainsItself() {
        let (provider, securityCLI, _, _, _) = makeSUT()
        securityCLI.failure = .timedOut

        #expect(provider.currentToken() == nil)
        #expect(provider.tokenDiagnostic.source == nil)
        #expect(provider.tokenDiagnostic.keychainFailure == .timedOut)
        #expect(provider.tokenDiagnostic.authFailureHint != nil)
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
            "uuid:uuid:https://api.anthropic.com": ["token": "sk-ant-test-only-no-real-secret"]
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

        #expect(provider.currentToken() == "sk-ant-test-only-no-real-secret")
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

    // MARK: - refreshTokenIfChanged (account swap detection)

    @Test("refreshTokenIfChanged detects a rotated Keychain token and updates the cache")
    func refreshTokenIfChangedDetectsRotation() {
        let (provider, securityCLI, _, _, _) = makeSUT(securityCLIToken: "tok-A")

        // Prime the cache with account A's token.
        #expect(provider.currentToken() == "tok-A")

        // cswap rotates the Keychain item to account B's token.
        securityCLI.token = "tok-B"

        #expect(provider.refreshTokenIfChanged() == true)
        #expect(provider.currentToken() == "tok-B")
    }

    @Test("refreshTokenIfChanged returns false when the token is unchanged")
    func refreshTokenIfChangedNoChange() {
        let (provider, _, _, _, _) = makeSUT(securityCLIToken: "tok-A")

        #expect(provider.currentToken() == "tok-A")
        #expect(provider.refreshTokenIfChanged() == false)
        #expect(provider.currentToken() == "tok-A")
    }

    @Test("refreshTokenIfChanged keeps the cached token when all sources momentarily miss")
    func refreshTokenIfChangedKeepsCacheOnTransientMiss() {
        let (provider, securityCLI, _, _, _) = makeSUT(securityCLIToken: "tok-A")

        #expect(provider.currentToken() == "tok-A")

        // A transient read failure (no source available) must not drop a
        // working token.
        securityCLI.token = nil
        #expect(provider.refreshTokenIfChanged() == false)
        #expect(provider.currentToken() == "tok-A")
    }

    @Test("refreshTokenIfChanged treats first population as not-a-rotation")
    func refreshTokenIfChangedFirstReadIsNotRotation() {
        let (provider, _, _, _, _) = makeSUT(securityCLIToken: "tok-A")

        // No prior currentToken() call, so the cache is empty: the first read
        // establishes a baseline rather than signalling a swap.
        #expect(provider.refreshTokenIfChanged() == false)
    }
}

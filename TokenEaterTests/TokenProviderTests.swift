import Testing
import Foundation

@Suite("TokenProvider")
struct TokenProviderTests {

    // MARK: - Helpers

    /// Stands in for TokenEater's own native read of the Keychain item and
    /// counts every call, because that read is the one that puts a
    /// TokenEater-named prompt on screen (#225).
    final class NativeReaderSpy {
        var token: String?
        private(set) var calls = 0

        init(token: String? = nil) { self.token = token }

        var reader: TokenProvider.KeychainTokenReader {
            { [self] in
                calls += 1
                return token
            }
        }
    }

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

        let keychainReader: TokenProvider.KeychainTokenReader = { keychainToken }

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

    @Test("no native Keychain fallback when security CLI and credentials file miss")
    func noNativeFallbackWhenEarlierSourcesMiss() {
        let (provider, _, _, _, decryption) = makeSUT(
            securityCLIToken: nil,
            credentialsToken: nil,
            keychainToken: "keychain-token"
        )

        let token = provider.currentToken()

        #expect(token == nil)
        #expect(provider.tokenDiagnostic.source == nil)
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

    /// Detection answers from the item's attributes and leaves the token to
    /// the connect step, so an install with a Claude Code item reads the
    /// payload once rather than twice.
    @Test("hasTokenSource detects a listed Keychain item without reading its data")
    func hasTokenSourceViaListedItem() {
        let (provider, securityCLI, _, _, _) = makeSUT()
        securityCLI.itemListed = true

        #expect(provider.hasTokenSource() == true)
        #expect(securityCLI.hasItemCallCount == 1)
        #expect(securityCLI.readCallCount == 0)
    }

    /// The trade-off of answering from attributes: an item with no login in
    /// it, like the MCP-only shadow of #268, still counts as Claude Code being
    /// here. The missing login surfaces at Connect, which reads the payload.
    @Test("hasTokenSource counts a listed item even when it holds no usable login")
    func hasTokenSourceCountsShadowItem() {
        let (provider, securityCLI, _, _, _) = makeSUT()
        securityCLI.itemListed = true
        securityCLI.failure = .unusablePayload

        #expect(provider.hasTokenSource() == true)
        #expect(provider.currentToken() == nil)
        #expect(provider.tokenDiagnostic.keychainFailure == .unusablePayload)
    }

    @Test("hasTokenSource never falls back to TokenEater's own Keychain read")
    func hasTokenSourceIgnoresNativeRead() {
        let spy = NativeReaderSpy(token: "some-token")
        let provider = TokenProvider(
            securityCLIReader: MockSecurityCLIReader(),
            credentialsFileReader: MockCredentialsFileReader(),
            configReader: MockClaudeConfigReader(),
            decryptionService: MockElectronDecryptionService(),
            keychainReader: spy.reader
        )

        #expect(provider.hasTokenSource() == false)
        #expect(spy.calls == 0)
    }

    @Test("hasTokenSource returns false when nothing available")
    func hasTokenSourceReturnsFalse() {
        let (provider, _, _, _, _) = makeSUT()
        #expect(provider.hasTokenSource() == false)
    }

    @Test("a config.json token never reaches the native Keychain read")
    func configJsonWithoutNativeRead() {
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

        let keychainReader: TokenProvider.KeychainTokenReader = {
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

    @Test("re-deriving the decryption key recovers a config.json token")
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
            keychainReader: { nil }
        )

        let token = provider.currentToken()

        #expect(token == "recovered-token")
        #expect(decryption.silentRebootstrapCallCount == 1)
        #expect(decryption.decryptCallCount == 1)
    }

    @Test("no native Keychain read when config.json is unavailable")
    func noNativeReadWhenConfigUnavailable() {
        let securityCLI = MockSecurityCLIReader()
        let credentials = MockCredentialsFileReader()
        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = nil // no config.json

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = false

        let spy = NativeReaderSpy(token: "keychain-fallback")
        let provider = TokenProvider(
            securityCLIReader: securityCLI,
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption,
            keychainReader: spy.reader
        )

        #expect(provider.currentToken() == nil)
        #expect(spy.calls == 0)
    }

    // MARK: - No native Keychain read on automatic paths (#225)

    /// The exact shape of the report: `security` fails, there is no file or
    /// Desktop token behind it, and the app keeps reading on launch, wake and
    /// every refresh tick. None of those may reach TokenEater's own read,
    /// whatever the reason the `security` read failed.
    @Test(
        "a failing security read never reaches the native Keychain read",
        arguments: [KeychainReadFailure.timedOut, .accessDenied, .unusablePayload, .notFound, .launchFailed, .unknown]
    )
    func failingSecurityReadNeverReachesNativeRead(failure: KeychainReadFailure) {
        let securityCLI = MockSecurityCLIReader()
        securityCLI.failure = failure
        securityCLI.itemListed = true
        let spy = NativeReaderSpy(token: "native-token")
        let provider = TokenProvider(
            securityCLIReader: securityCLI,
            credentialsFileReader: MockCredentialsFileReader(),
            configReader: MockClaudeConfigReader(),
            decryptionService: MockElectronDecryptionService(),
            keychainReader: spy.reader
        )

        // Launch / wake / retry: an empty cache read.
        #expect(provider.currentToken() == nil)
        // Several auto-refresh ticks.
        for _ in 0..<5 {
            #expect(provider.refreshTokenIfChanged() == false)
            #expect(provider.currentToken() == nil)
        }
        // A 401, then the read that follows it.
        provider.invalidateToken()
        #expect(provider.currentToken() == nil)
        // Onboarding detection and Check / Reset connection.
        _ = provider.hasTokenSource()
        #expect(provider.resetConnection() == nil)

        #expect(spy.calls == 0)
        #expect(provider.tokenDiagnostic.source == nil)
        #expect(provider.tokenDiagnostic.keychainFailure == failure)
    }

    /// A token already cached, then `security` starts failing (the macOS 26
    /// timeout, say): the tick keeps the working token and still never falls
    /// through to the native read.
    @Test("refresh ticks keep the cached token without a native read when security starts failing")
    func refreshTickKeepsCacheWithoutNativeRead() {
        let securityCLI = MockSecurityCLIReader()
        securityCLI.token = "tok-A"
        let spy = NativeReaderSpy(token: "native-token")
        let provider = TokenProvider(
            securityCLIReader: securityCLI,
            credentialsFileReader: MockCredentialsFileReader(),
            configReader: MockClaudeConfigReader(),
            decryptionService: MockElectronDecryptionService(),
            keychainReader: spy.reader
        )

        #expect(provider.currentToken() == "tok-A")
        securityCLI.token = nil
        securityCLI.failure = .timedOut

        #expect(provider.refreshTokenIfChanged() == false)
        #expect(provider.currentToken() == "tok-A")
        #expect(spy.calls == 0)
    }

    /// The interactive read survives only behind `bootstrap()`, which nothing
    /// calls today; wiring it up is a decision about accepting the prompt.
    @Test("bootstrap still reaches the native Keychain read")
    func bootstrapReachesNativeRead() throws {
        let spy = NativeReaderSpy(token: "native-token")
        let provider = TokenProvider(
            securityCLIReader: MockSecurityCLIReader(),
            credentialsFileReader: MockCredentialsFileReader(),
            configReader: MockClaudeConfigReader(),
            decryptionService: MockElectronDecryptionService(),
            keychainReader: spy.reader
        )

        try provider.bootstrap()

        #expect(spy.calls == 1)
        #expect(provider.currentToken() == "native-token")
    }

    // MARK: - Claude Desktop key re-derivation stays off the tick

    /// The same bug through the Claude Desktop path: `security` fails, the
    /// only token is in config.json, and no decryption key is cached. The
    /// "Claude Safe Storage" read behind the re-derivation can prompt in
    /// TokenEater's name, so the ticks must not retry it.
    @Test("a failing key re-derivation is tried once, not on every refresh tick")
    func keyRederivationIsNotRetriedPerTick() {
        let (provider, securityCLI, _, _, decryption) = makeSUT(encryptedToken: "encrypted-blob")
        securityCLI.failure = .accessDenied
        decryption.silentRebootstrapResult = false

        #expect(provider.currentToken() == nil)
        for _ in 0..<5 {
            #expect(provider.refreshTokenIfChanged() == false)
            #expect(provider.currentToken() == nil)
        }
        provider.invalidateToken()
        #expect(provider.currentToken() == nil)

        #expect(decryption.silentRebootstrapCallCount == 1)
    }

    /// Reset connection is a click, not a timer, so it earns one more try.
    @Test("Reset connection re-arms the key re-derivation once")
    func resetConnectionRearmsKeyRederivation() {
        let oauthJSON: [String: Any] = ["claudeAiOauth": ["accessToken": "desktop-token"]]
        let (provider, securityCLI, _, _, decryption) = makeSUT(
            encryptedToken: "encrypted-blob",
            decryptedData: try! JSONSerialization.data(withJSONObject: oauthJSON)
        )
        securityCLI.failure = .accessDenied

        #expect(provider.currentToken() == nil)
        #expect(provider.refreshTokenIfChanged() == false)
        #expect(decryption.silentRebootstrapCallCount == 1)

        decryption.silentRebootstrapResult = true
        #expect(provider.resetConnection() == "desktop-token")
        #expect(decryption.silentRebootstrapCallCount == 2)
        #expect(provider.tokenDiagnostic.source == .claudeDesktop)

        // With the key cached again, later ticks decrypt without re-deriving.
        #expect(provider.refreshTokenIfChanged() == false)
        #expect(decryption.silentRebootstrapCallCount == 2)
    }

    // MARK: - Freshness over priority (#268)

    private let expiredAt = Date().addingTimeInterval(-3 * 3600)
    private let validUntil = Date().addingTimeInterval(5 * 3600)

    /// The report: the user works in the Claude desktop app, the CLI's
    /// Keychain item expired hours ago, and Desktop's embedded engine keeps
    /// `.credentials.json` current. The live file token has to win.
    @Test("an expired Keychain token gives way to a valid credentials file")
    func expiredKeychainYieldsToValidFile() {
        let (provider, securityCLI, credentials, _, _) = makeSUT(
            securityCLIToken: "stale-keychain",
            credentialsToken: "fresh-file"
        )
        securityCLI.expiresAt = expiredAt
        credentials.storedExpiresAt = validUntil

        #expect(provider.currentToken() == "fresh-file")
        let diagnostic = provider.tokenDiagnostic
        #expect(diagnostic.source == .credentialsFile)
        #expect(diagnostic.tokenExpiresAt == validUntil)
        #expect(diagnostic.keychainExpiresAt == expiredAt)
        #expect(diagnostic.keychainFailure == nil)
        #expect(diagnostic.passedOverExpiredKeychain)
        #expect(diagnostic.isStaleFallback == false)
    }

    /// Nothing better anywhere: the expired Keychain token is still returned,
    /// so the request is made, the 401 path runs, and the diagnostic carries
    /// the expiry the escalation needs.
    @Test("an expired Keychain token is kept when no other source has a token")
    func expiredKeychainKeptWhenAlone() {
        let (provider, securityCLI, _, _, _) = makeSUT(securityCLIToken: "stale-keychain")
        securityCLI.expiresAt = expiredAt

        #expect(provider.currentToken() == "stale-keychain")
        let diagnostic = provider.tokenDiagnostic
        #expect(diagnostic.source == .keychainCLI)
        #expect(diagnostic.tokenExpiresAt == expiredAt)
        #expect(diagnostic.loginExpiresAt == expiredAt)
        #expect(diagnostic.passedOverExpiredKeychain == false)
    }

    @Test("a valid Keychain token wins over a valid credentials file")
    func validKeychainWins() {
        let (provider, securityCLI, credentials, _, decryption) = makeSUT(
            securityCLIToken: "live-keychain",
            credentialsToken: "live-file",
            encryptedToken: "encrypted-blob",
            hasEncryptionKey: true
        )
        securityCLI.expiresAt = validUntil
        credentials.storedExpiresAt = validUntil.addingTimeInterval(3600)

        #expect(provider.currentToken() == "live-keychain")
        #expect(provider.tokenDiagnostic.source == .keychainCLI)
        #expect(decryption.decryptCallCount == 0)
    }

    /// Two dead tokens: priority decides, so the Keychain one, which is the
    /// login Claude Code renews, is the one the diagnostic talks about.
    @Test("with every token expired the Keychain one is kept")
    func allExpiredKeepsKeychain() {
        let (provider, securityCLI, credentials, _, _) = makeSUT(
            securityCLIToken: "stale-keychain",
            credentialsToken: "stale-file"
        )
        securityCLI.expiresAt = expiredAt
        credentials.storedExpiresAt = expiredAt.addingTimeInterval(-3600)

        #expect(provider.currentToken() == "stale-keychain")
        #expect(provider.tokenDiagnostic.source == .keychainCLI)
    }

    @Test("a token about to expire counts as expired")
    func nearlyExpiredKeychainYields() {
        let (provider, securityCLI, credentials, _, _) = makeSUT(
            securityCLIToken: "dying-keychain",
            credentialsToken: "fresh-file"
        )
        securityCLI.expiresAt = Date().addingTimeInterval(20)
        credentials.storedExpiresAt = validUntil

        #expect(provider.currentToken() == "fresh-file")
    }

    /// No expiry is not a dead token: a Keychain payload without one keeps
    /// its priority, exactly as before.
    @Test("a Keychain token with no expiry keeps its priority")
    func keychainWithoutExpiryKeepsPriority() {
        let (provider, _, credentials, _, _) = makeSUT(
            securityCLIToken: "keychain",
            credentialsToken: "file"
        )
        credentials.storedExpiresAt = validUntil

        #expect(provider.currentToken() == "keychain")
    }

    @Test("an expired Keychain token gives way to a Claude Desktop token")
    func expiredKeychainYieldsToDesktop() {
        let desktopJSON: [String: Any] = [
            "claudeAiOauth": [
                "accessToken": "desktop-token",
                "expiresAt": validUntil.timeIntervalSince1970 * 1000,
            ]
        ]
        let (provider, securityCLI, _, _, _) = makeSUT(
            securityCLIToken: "stale-keychain",
            encryptedToken: "encrypted-blob",
            hasEncryptionKey: true,
            decryptedData: try! JSONSerialization.data(withJSONObject: desktopJSON)
        )
        securityCLI.expiresAt = expiredAt

        #expect(provider.currentToken() == "desktop-token")
        #expect(provider.tokenDiagnostic.source == .claudeDesktop)
        #expect(provider.tokenDiagnostic.passedOverExpiredKeychain)
    }

    /// Looking for a fresher token must not cost a prompt: with no cached
    /// Desktop key, the search skips that source rather than re-deriving
    /// the key from "Claude Safe Storage" (#225).
    @Test("the freshness search never re-derives the Claude Desktop key")
    func freshnessSearchDoesNotRederiveKey() {
        let (provider, securityCLI, _, _, decryption) = makeSUT(
            securityCLIToken: "stale-keychain",
            encryptedToken: "encrypted-blob",
            hasEncryptionKey: false
        )
        securityCLI.expiresAt = expiredAt
        decryption.silentRebootstrapResult = true

        #expect(provider.currentToken() == "stale-keychain")
        for _ in 0..<3 { _ = provider.refreshTokenIfChanged() }
        #expect(decryption.silentRebootstrapCallCount == 0)
    }

    /// Desktop writes a renewed login to the file: the next tick picks it up
    /// as a change, which forces the refresh that clears the stale state.
    @Test("a renewed file token behind an expired Keychain is seen on the next tick")
    func renewedFileSeenOnTick() {
        let (provider, securityCLI, credentials, _, _) = makeSUT(
            securityCLIToken: "stale-keychain",
            credentialsToken: "stale-file"
        )
        securityCLI.expiresAt = expiredAt
        credentials.storedExpiresAt = expiredAt

        #expect(provider.currentToken() == "stale-keychain")

        credentials.storedToken = "renewed-file"
        credentials.storedExpiresAt = validUntil

        #expect(provider.refreshTokenIfChanged() == true)
        #expect(provider.currentToken() == "renewed-file")
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

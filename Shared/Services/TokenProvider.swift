import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "TokenProvider")

final class TokenProvider: TokenProviderProtocol, @unchecked Sendable {
    private let securityCLIReader: SecurityCLIReaderProtocol
    private let credentialsFileReader: CredentialsFileReaderProtocol
    private let configReader: ClaudeConfigReaderProtocol
    private let decryptionService: ElectronDecryptionServiceProtocol
    private let keychainReader: KeychainTokenReader

    /// In-memory token cache - avoids hitting the Keychain on every refresh.
    /// Only cleared on 401 (token expired) via `invalidateToken()`.
    private var cachedToken: String?

    /// What the last full read found. Kept alongside the cache so a 401 can be
    /// explained by where the token came from rather than by assuming it
    /// expired (#273).
    private var diagnostic: TokenDiagnostic = .unknown

    var tokenDiagnostic: TokenDiagnostic { diagnostic }

    /// Whether this launch already tried to re-derive the Claude Desktop key
    /// from "Claude Safe Storage". That read goes through TokenEater's own
    /// identity too, and `kSecUseAuthenticationUISkip` does not keep it quiet
    /// either, so it gets one try per launch rather than one per refresh tick.
    /// Only `resetConnection()`, an explicit user action, re-arms it.
    private var safeStorageRebootstrapAttempted = false

    /// Reads Claude Code's Keychain item with TokenEater's own identity, the
    /// one read that makes macOS name TokenEater in its "wants to access"
    /// dialog. There is no silent form of it: `kSecUseAuthenticationUISkip`
    /// does not suppress that ACL prompt, and Claude Code resets the item's
    /// ACL on every token rotation, so an "Always Allow" given to TokenEater
    /// lasts only until the next one. Only `bootstrap()` calls it, never an
    /// automatic path (#225).
    typealias KeychainTokenReader = () -> String?

    init(
        securityCLIReader: SecurityCLIReaderProtocol = SecurityCLIReader(),
        credentialsFileReader: CredentialsFileReaderProtocol = CredentialsFileReader(),
        configReader: ClaudeConfigReaderProtocol = ClaudeConfigReader(),
        decryptionService: ElectronDecryptionServiceProtocol = ElectronDecryptionService(),
        keychainReader: KeychainTokenReader? = nil
    ) {
        self.securityCLIReader = securityCLIReader
        self.credentialsFileReader = credentialsFileReader
        self.configReader = configReader
        self.decryptionService = decryptionService
        self.keychainReader = keychainReader ?? Self.defaultKeychainReader
    }

    var isBootstrapped: Bool { true }

    /// Onboarding's "is Claude Code here" check. It answers from the
    /// Keychain item's attributes, which no ACL guards, rather than from its
    /// data: reading the token is `currentToken()`'s job a step later, and
    /// reading it here too doubled the reads a fresh install makes. The
    /// `security` read at the end only runs when the listing saw no item, so
    /// a listing that comes back empty on some setup cannot hide a working
    /// login behind a "not installed" card.
    func hasTokenSource() -> Bool {
        if cachedToken != nil { return true }
        if securityCLIReader.hasCredentialItem() { return true }
        if credentialsFileReader.readToken() != nil { return true }
        if configReader.readEncryptedToken() != nil { return true }
        if securityCLIReader.readToken() != nil { return true }
        return false
    }

    /// Returns the current token, using the in-memory cache if available.
    /// The Keychain is only read when the cache is empty (app start, or after `invalidateToken()`).
    ///
    /// Source priority (v5.0+):
    /// 1. `/usr/bin/security` shell-out (primary - works for all modern Claude Code macOS users,
    ///    no popups across app updates because `security` has a stable Apple signing identity;
    ///    guarded by a 3s watchdog so a hung child can't block - see SecurityCLIReader)
    /// 2. `.credentials.json` (legacy Claude Code fallback - still present on Linux/Windows and
    ///    on very old macOS Claude Code installs)
    /// 3. Claude Desktop `config.json` decryption (for users without Claude Code CLI at all)
    ///
    /// There is no fourth source. A direct `SecItemCopyMatching` read used to
    /// close the list "as a silent read", but it was never silent, and with
    /// `refreshTokenIfChanged()` running the list on every auto-refresh tick
    /// it put a TokenEater-named Keychain prompt on a timer whenever the
    /// `security` read failed (#225).
    func currentToken() -> String? {
        if let token = cachedToken { return token }
        let token = readFromSources()
        cachedToken = token
        return token
    }

    /// Reads the token from all sources in priority order, bypassing the
    /// in-memory cache. Returns the freshest token currently on the system.
    private func readFromSources() -> String? {
        let keychain = securityCLIReader.read()
        let items = keychain.matchingItems

        if let token = keychain.token {
            logger.info("Token read via /usr/bin/security")
            diagnostic = TokenDiagnostic(
                source: .keychainCLI,
                keychainFailure: nil,
                matchingKeychainItems: items,
                tokenExpiresAt: keychain.expiresAt
            )
            return token
        }
        // The failure is carried through the fall-through rather than logged
        // and dropped, so the caller can tell a machine that keeps its
        // credentials in a file from one whose live token we were refused.
        let keychainFailure = keychain.failure
        logger.info("security read failed: \(keychainFailure?.rawValue ?? "unknown", privacy: .public)")

        if let token = credentialsFileReader.readToken() {
            diagnostic = TokenDiagnostic(source: .credentialsFile, keychainFailure: keychainFailure, matchingKeychainItems: items)
            return token
        }

        if let token = tokenFromConfigJSON() {
            diagnostic = TokenDiagnostic(source: .claudeDesktop, keychainFailure: keychainFailure, matchingKeychainItems: items)
            return token
        }

        // No direct native read of the Keychain item here, on purpose: this
        // runs on launch, wake and every refresh tick, and that read prompts
        // in TokenEater's name (#225). A failed `security` read is reported
        // through the diagnostic instead.
        diagnostic = TokenDiagnostic(source: nil, keychainFailure: keychainFailure, matchingKeychainItems: items)
        return nil
    }

    /// Re-reads the token from its sources and updates the cache when it
    /// changed. The file watcher only sees `config.json` / `.credentials.json`,
    /// but on modern macOS the active token lives in the Keychain - so a
    /// `cswap`/`claude login` account swap rotates the Keychain item with no
    /// filesystem event and the cache would otherwise keep serving the previous
    /// account's token until a 401. Polling here (on the auto-refresh tick)
    /// closes that gap. Returns true only on an actual change between two
    /// non-nil tokens; first population and transient read failures return false
    /// so a working token is never dropped.
    func refreshTokenIfChanged() -> Bool {
        guard let fresh = readFromSources() else { return false }
        let previous = cachedToken
        cachedToken = fresh
        guard let previous else { return false }
        if previous != fresh {
            logger.info("Token changed on Keychain/disk - cache refreshed for new account")
            return true
        }
        return false
    }

    /// Decrypts Claude Desktop's config.json with the cached key. Without a
    /// working key it re-derives one from "Claude Safe Storage", at most once
    /// per launch: that Keychain read can show a TokenEater-named dialog, and
    /// this path runs on every refresh tick, so retrying it here would bring
    /// back the recurring prompt of #225 for Claude Desktop users.
    private func tokenFromConfigJSON() -> String? {
        guard let encrypted = configReader.readEncryptedToken() else { return nil }

        if decryptionService.hasEncryptionKey,
           let token = decryptFromConfigJSON(encrypted) {
            return token
        }

        guard !safeStorageRebootstrapAttempted else { return nil }
        safeStorageRebootstrapAttempted = true

        if decryptionService.trySilentRebootstrap(),
           let token = decryptFromConfigJSON(encrypted) {
            logger.info("Token recovered by re-deriving the Claude Desktop decryption key")
            return token
        }

        return nil
    }

    /// Call this after a 401 - clears the in-memory cache so the next `currentToken()`
    /// re-reads from Keychain/file to pick up a refreshed token.
    func invalidateToken() {
        cachedToken = nil
        logger.info("Token cache invalidated - next read will check Keychain")
    }

    /// Forgets everything the app learned about the connection and reads it
    /// again from scratch: the in-memory token and the cached Claude Desktop
    /// decryption key, which survives a relaunch and can outlive the account
    /// it was derived for. Being a click rather than a timer, it also allows
    /// one more attempt at re-deriving that key.
    ///
    /// It touches nothing the user configured, which is the whole point of
    /// the request behind it: people were reinstalling the app, and losing
    /// every setting, to get back a connection (#268).
    func resetConnection() -> String? {
        cachedToken = nil
        diagnostic = .unknown
        safeStorageRebootstrapAttempted = false
        decryptionService.clearCachedKey()
        logger.info("Connection reset: caches dropped, re-reading sources")
        return currentToken()
    }

    func bootstrap() throws {
        if let token = keychainReader() {
            cachedToken = token
            logger.info("Bootstrap succeeded via interactive Keychain read")
        }

        do {
            try decryptionService.bootstrapEncryptionKey()
        } catch {
            logger.info("Decryption key bootstrap skipped: \(error)")
        }
    }

    // MARK: - Keychain (static, no instance state)

    private static func defaultKeychainReader() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }

        return token
    }

    // MARK: - Config.json Decryption (fallback)

    private func decryptFromConfigJSON(_ encrypted: String) -> String? {
        do {
            let data = try decryptionService.decrypt(encrypted)
            return Self.extractToken(from: data)
        } catch {
            return nil
        }
    }

    private static func extractToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            return token
        }
        for (_, value) in json {
            if let entry = value as? [String: Any],
               let token = entry["token"] as? String,
               token.hasPrefix("sk-ant-") {
                return token
            }
        }
        return nil
    }
}

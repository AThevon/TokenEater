import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "TokenProvider")

final class TokenProvider: TokenProviderProtocol, @unchecked Sendable {
    /// The four sources one scope reads, in priority order.
    struct Readers {
        let securityCLI: SecurityCLIReaderProtocol
        let credentialsFile: CredentialsFileReaderProtocol
        let config: ClaudeConfigReaderProtocol
        let decryption: ElectronDecryptionServiceProtocol
        let keychain: KeychainTokenReader
    }

    typealias ReaderFactory = (CredentialScope) -> Readers

    private var securityCLIReader: SecurityCLIReaderProtocol
    private var credentialsFileReader: CredentialsFileReaderProtocol
    private var configReader: ClaudeConfigReaderProtocol
    private var decryptionService: ElectronDecryptionServiceProtocol
    private var keychainReader: KeychainTokenReader
    /// Builds the readers for a scope on `reconfigure(scope:)`.
    private let makeReaders: ReaderFactory
    private var currentScope: CredentialScope

    var scope: CredentialScope { withState { currentScope } }

    /// The stores read their token off the main thread, so the provider is
    /// reached from several threads. `stateLock` guards every field and is
    /// only ever held for an assignment, never across a read of the sources,
    /// so the main thread asking for the scope or the diagnostic never waits
    /// on a `security` child. `readLock` serializes the reads themselves:
    /// two refreshes never run the same `security` read twice at once.
    private let stateLock = NSLock()
    private let readLock = NSLock()
    /// Bumped whenever the cache is dropped. A read that started before
    /// does not put its token back in the cache.
    private var cacheEpoch = 0
    /// Bumped when the provider moves to another scope. A read that started
    /// before answers nothing: its token belongs to the previous folder.
    private var scopeEpoch = 0

    private func withState<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    /// The readers and epochs a read works with, taken in one go.
    private struct ReadContext {
        let securityCLI: SecurityCLIReaderProtocol
        let credentialsFile: CredentialsFileReaderProtocol
        let config: ClaudeConfigReaderProtocol
        let decryption: ElectronDecryptionServiceProtocol
        let cacheEpoch: Int
        let scopeEpoch: Int
    }

    private func readContext() -> ReadContext {
        withState {
            ReadContext(
                securityCLI: securityCLIReader,
                credentialsFile: credentialsFileReader,
                config: configReader,
                decryption: decryptionService,
                cacheEpoch: cacheEpoch,
                scopeEpoch: scopeEpoch
            )
        }
    }

    /// In-memory token cache - avoids hitting the Keychain on every refresh.
    /// Only cleared on 401 (token expired) via `invalidateToken()`.
    private var cachedToken: String?

    /// What the last full read found. Kept alongside the cache so a 401 can be
    /// explained by where the token came from rather than by assuming it
    /// expired (#273).
    private var diagnostic: TokenDiagnostic = .unknown

    var tokenDiagnostic: TokenDiagnostic { withState { diagnostic } }

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
        keychainReader: KeychainTokenReader? = nil,
        scope: CredentialScope = .defaultChain,
        readerFactory: ReaderFactory? = nil
    ) {
        self.securityCLIReader = securityCLIReader
        self.credentialsFileReader = credentialsFileReader
        self.configReader = configReader
        self.decryptionService = decryptionService
        self.keychainReader = keychainReader ?? { Self.nativeKeychainRead(service: ClaudeConfigDirResolver.baseService) }
        self.currentScope = scope
        self.makeReaders = readerFactory ?? { Self.readers(for: $0) }
    }

    /// A provider bounded to one account's sources. `.defaultChain` builds
    /// exactly the readers the app has always used; `.configDir` reads that
    /// folder's exact Keychain service and its `.credentials.json`, and never
    /// Claude Desktop, so a token can only ever belong to that folder.
    convenience init(scope: CredentialScope, home: String = ClaudeConfigDirResolver.realHome()) {
        let readers = Self.readers(for: scope, home: home)
        self.init(
            securityCLIReader: readers.securityCLI,
            credentialsFileReader: readers.credentialsFile,
            configReader: readers.config,
            decryptionService: readers.decryption,
            keychainReader: readers.keychain,
            scope: scope,
            readerFactory: { Self.readers(for: $0, home: home) }
        )
    }

    /// The main account's provider, scoped to the folder the user chose for
    /// it, or to the default chain when they never chose one (#294). Only
    /// reads `UserDefaults`; nothing touches a credential until a token is
    /// asked for.
    static func forMainAccount(defaults: UserDefaults = .standard) -> TokenProvider {
        let main = ClaudeAccountsStorage.load(from: defaults).first ?? .defaultMain()
        return TokenProvider(scope: main.scope)
    }

    /// The readers a scope is allowed to use.
    static func readers(
        for scope: CredentialScope,
        home: String = ClaudeConfigDirResolver.realHome()
    ) -> Readers {
        switch scope {
        case .defaultChain:
            return Readers(
                securityCLI: SecurityCLIReader(),
                credentialsFile: CredentialsFileReader(filePath: scope.credentialsFilePath(home: home)),
                config: ClaudeConfigReader(),
                decryption: ElectronDecryptionService(),
                keychain: { nativeKeychainRead(service: ClaudeConfigDirResolver.baseService) }
            )
        case .configDir(_, let service):
            return Readers(
                securityCLI: SecurityCLIReader(service: service),
                credentialsFile: CredentialsFileReader(filePath: scope.credentialsFilePath(home: home)),
                config: NoClaudeDesktopConfig(),
                decryption: NoDecryptionService(),
                keychain: { nativeKeychainRead(service: service) }
            )
        }
    }

    /// Points the provider at another scope. Drops everything tied to the
    /// previous one (cached token, diagnostic, the once-per-launch Desktop
    /// key attempt) and reads nothing: the next `currentToken()` does.
    func reconfigure(scope: CredentialScope) {
        let readers = makeReaders(scope)
        withState {
            securityCLIReader = readers.securityCLI
            credentialsFileReader = readers.credentialsFile
            configReader = readers.config
            decryptionService = readers.decryption
            keychainReader = readers.keychain
            currentScope = scope
            cachedToken = nil
            diagnostic = .unknown
            safeStorageRebootstrapAttempted = false
            cacheEpoch += 1
            scopeEpoch += 1
        }
        logger.info("Token scope reconfigured")
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
        if withState({ cachedToken }) != nil { return true }
        let context = readContext()
        if context.securityCLI.hasCredentialItem() { return true }
        if context.credentialsFile.readToken() != nil { return true }
        if context.config.readEncryptedToken() != nil { return true }
        if context.securityCLI.readToken() != nil { return true }
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
    /// A token known to be expired gives way to the next source that holds a
    /// live one, and is used only when none does (see `readFromSources`).
    ///
    /// There is no fourth source. A direct `SecItemCopyMatching` read used to
    /// close the list "as a silent read", but it was never silent, and with
    /// `refreshTokenIfChanged()` running the list on every auto-refresh tick
    /// it put a TokenEater-named Keychain prompt on a timer whenever the
    /// `security` read failed (#225).
    func currentToken() -> String? {
        if let token = withState({ cachedToken }) { return token }
        readLock.lock()
        defer { readLock.unlock() }
        // Another thread may have filled the cache while this one waited.
        if let token = withState({ cachedToken }) { return token }
        let context = readContext()
        let token = readFromSources(context)
        return withState {
            guard scopeEpoch == context.scopeEpoch else { return nil }
            if cacheEpoch == context.cacheEpoch { cachedToken = token }
            return token
        }
    }

    /// Reads the token from all sources in priority order, bypassing the
    /// in-memory cache. Returns the freshest token currently on the system.
    ///
    /// Priority alone is not enough: the Keychain item is only renewed when
    /// the Claude Code CLI runs, and someone who works in the Claude desktop
    /// app can leave it expired for a day while Desktop's embedded engine
    /// keeps `.credentials.json` current (anthropics/claude-code#94464). So
    /// the first source whose token is not known to be expired wins, and an
    /// expired one is used only when nothing better exists, which keeps the
    /// 401 path and its diagnostic working (#268). Nothing here writes or
    /// refreshes anything.
    private func readFromSources(_ context: ReadContext, now: Date = Date()) -> String? {
        let keychain = context.securityCLI.read()
        let items = keychain.matchingItems
        // The failure is carried through the fall-through rather than logged
        // and dropped, so the caller can tell a machine that keeps its
        // credentials in a file from one whose live token we were refused.
        let keychainFailure = keychain.failure

        func record(_ source: TokenSource?, _ credential: ClaudeCredential?) {
            let next = TokenDiagnostic(
                source: source,
                keychainFailure: keychainFailure,
                matchingKeychainItems: items,
                tokenExpiresAt: credential?.expiresAt,
                keychainExpiresAt: keychain.token != nil ? keychain.expiresAt : nil
            )
            withState {
                // A read that outlived a move to another folder describes
                // the previous one.
                if scopeEpoch == context.scopeEpoch { diagnostic = next }
            }
        }

        // The first expired token met, kept in case nothing fresher turns up.
        var expired: (source: TokenSource, credential: ClaudeCredential)?

        if let token = keychain.token {
            let credential = ClaudeCredential(token: token, expiresAt: keychain.expiresAt)
            guard TokenExpiryPolicy.isExpired(credential.expiresAt, now: now) else {
                logger.info("Token read via /usr/bin/security")
                record(.keychainCLI, credential)
                return token
            }
            logger.info("Keychain token expired; looking for a fresher source")
            expired = (.keychainCLI, credential)
        } else {
            logger.info("security read failed: \(keychainFailure?.rawValue ?? "unknown", privacy: .public)")
        }

        if let credential = context.credentialsFile.readCredential() {
            if !TokenExpiryPolicy.isExpired(credential.expiresAt, now: now) {
                record(.credentialsFile, credential)
                return credential.token
            }
            expired = expired ?? (.credentialsFile, credential)
        }

        // Re-deriving the Claude Desktop key can prompt in TokenEater's name,
        // so the search for a fresher token only uses a key already cached.
        // Only the plain fall-through, with no token anywhere else, may try
        // it, exactly as before.
        if let credential = tokenFromConfigJSON(context, mayRederiveKey: expired == nil) {
            if expired == nil || !TokenExpiryPolicy.isExpired(credential.expiresAt, now: now) {
                record(.claudeDesktop, credential)
                return credential.token
            }
        }

        if let expired {
            record(expired.source, expired.credential)
            return expired.credential.token
        }

        // No direct native read of the Keychain item here, on purpose: this
        // runs on launch, wake and every refresh tick, and that read prompts
        // in TokenEater's name (#225). A failed `security` read is reported
        // through the diagnostic instead.
        record(nil, nil)
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
        readLock.lock()
        defer { readLock.unlock() }
        let context = readContext()
        guard let fresh = readFromSources(context) else { return false }
        let changed: Bool = withState {
            guard scopeEpoch == context.scopeEpoch else { return false }
            let previous = cachedToken
            cachedToken = fresh
            guard let previous else { return false }
            return previous != fresh
        }
        if changed {
            logger.info("Token changed on Keychain/disk - cache refreshed for new account")
        }
        return changed
    }

    /// Decrypts Claude Desktop's config.json with the cached key. Without a
    /// working key it re-derives one from "Claude Safe Storage", at most once
    /// per launch: that Keychain read can show a TokenEater-named dialog, and
    /// this path runs on every refresh tick, so retrying it here would bring
    /// back the recurring prompt of #225 for Claude Desktop users. A caller
    /// that already holds a token passes `mayRederiveKey: false`, so looking
    /// for a fresher one never costs a prompt.
    private func tokenFromConfigJSON(_ context: ReadContext, mayRederiveKey: Bool) -> ClaudeCredential? {
        guard let encrypted = context.config.readEncryptedToken() else { return nil }
        let decryption = context.decryption

        if decryption.hasEncryptionKey,
           let credential = decryptFromConfigJSON(encrypted, using: decryption) {
            return credential
        }

        guard mayRederiveKey else { return nil }
        let mayTry: Bool = withState {
            guard !safeStorageRebootstrapAttempted else { return false }
            safeStorageRebootstrapAttempted = true
            return true
        }
        guard mayTry else { return nil }

        if decryption.trySilentRebootstrap(),
           let credential = decryptFromConfigJSON(encrypted, using: decryption) {
            logger.info("Token recovered by re-deriving the Claude Desktop decryption key")
            return credential
        }

        return nil
    }

    /// Call this after a 401 - clears the in-memory cache so the next `currentToken()`
    /// re-reads from Keychain/file to pick up a refreshed token.
    func invalidateToken() {
        withState {
            cachedToken = nil
            cacheEpoch += 1
        }
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
        let decryption: ElectronDecryptionServiceProtocol = withState {
            cachedToken = nil
            diagnostic = .unknown
            safeStorageRebootstrapAttempted = false
            cacheEpoch += 1
            return decryptionService
        }
        decryption.clearCachedKey()
        logger.info("Connection reset: caches dropped, re-reading sources")
        return currentToken()
    }

    func bootstrap() throws {
        let (reader, decryption) = withState { (keychainReader, decryptionService) }
        if let token = reader() {
            withState { cachedToken = token }
            logger.info("Bootstrap succeeded via interactive Keychain read")
        }

        do {
            try decryption.bootstrapEncryptionKey()
        } catch {
            logger.info("Decryption key bootstrap skipped: \(error)")
        }
    }

    // MARK: - Keychain (static, no instance state)

    private static func nativeKeychainRead(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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

    private func decryptFromConfigJSON(
        _ encrypted: String,
        using decryption: ElectronDecryptionServiceProtocol
    ) -> ClaudeCredential? {
        do {
            let data = try decryption.decrypt(encrypted)
            return Self.extractCredential(from: data)
        } catch {
            return nil
        }
    }

    /// The expiry is read when the payload carries one, in either shape, so a
    /// dead Desktop token is not preferred over a dead Keychain one.
    private static func extractCredential(from data: Data) -> ClaudeCredential? {
        if let credential = ClaudeCredential.parse(data) { return credential }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for (_, value) in json {
            if let entry = value as? [String: Any],
               let token = entry["token"] as? String,
               token.hasPrefix("sk-ant-") {
                return ClaudeCredential(token: token, expiresAt: ClaudeCredential.expiry(from: entry["expiresAt"]))
            }
        }
        return nil
    }
}

// MARK: - Scoped no-op sources

/// Claude Desktop's login is not tied to any `CLAUDE_CONFIG_DIR`, so a folder
/// scope never reads it.
private struct NoClaudeDesktopConfig: ClaudeConfigReaderProtocol {
    func readEncryptedToken() -> String? { nil }
}

/// The decryption a folder scope never needs. No migration in its init and
/// nothing to clear, so resetting an added account's connection leaves the
/// main account's cached `decryption.key` alone.
private struct NoDecryptionService: ElectronDecryptionServiceProtocol {
    func decrypt(_ encryptedBase64: String) throws -> Data { throw ElectronDecryptionError.keyDerivationFailed }
    var hasEncryptionKey: Bool { false }
    func bootstrapEncryptionKey() throws {}
    func clearCachedKey() {}
    func trySilentRebootstrap() -> Bool { false }
}

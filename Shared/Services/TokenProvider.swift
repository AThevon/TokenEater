import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "TokenProvider")

final class TokenProvider: TokenProviderProtocol, @unchecked Sendable {
    private let credentialsFileReader: CredentialsFileReaderProtocol
    private let keychainHelperReader: KeychainHelperReaderProtocol
    private let configReader: ClaudeConfigReaderProtocol
    private let decryptionService: ElectronDecryptionServiceProtocol
    private let keychainReader: KeychainTokenReader

    /// In-memory token cache - avoids hitting the Keychain on every refresh.
    /// Only cleared on 401 (token expired) via `invalidateToken()`.
    private var cachedToken: String?

    /// Closure type for reading from the Keychain. `silent` = use kSecUseAuthenticationUISkip.
    typealias KeychainTokenReader = (_ silent: Bool) -> String?

    init(
        credentialsFileReader: CredentialsFileReaderProtocol = CredentialsFileReader(),
        keychainHelperReader: KeychainHelperReaderProtocol = KeychainHelperReader(),
        configReader: ClaudeConfigReaderProtocol = ClaudeConfigReader(),
        decryptionService: ElectronDecryptionServiceProtocol = ElectronDecryptionService(),
        keychainReader: KeychainTokenReader? = nil
    ) {
        self.credentialsFileReader = credentialsFileReader
        self.keychainHelperReader = keychainHelperReader
        self.configReader = configReader
        self.decryptionService = decryptionService
        self.keychainReader = keychainReader ?? Self.defaultKeychainReader
    }

    var isBootstrapped: Bool { true }

    func hasTokenSource() -> Bool {
        if cachedToken != nil { return true }
        if credentialsFileReader.readToken() != nil { return true }
        if keychainHelperReader.readToken() != nil { return true }
        if configReader.readEncryptedToken() != nil { return true }
        if keychainReader(true) != nil { return true }
        return false
    }

    /// Returns the current token, using the in-memory cache if available.
    /// The Keychain is only read when the cache is empty (app start, or after `invalidateToken()`).
    func currentToken() -> String? {
        if let token = cachedToken { return token }

        // Source 1: credentials file (legacy Claude Code that still wrote it)
        if let token = credentialsFileReader.readToken() {
            cachedToken = token
            return token
        }

        // Source 2: helper-synced Keychain token (new Claude Code CLI). Reads a
        // JSON file the helper LaunchAgent writes - no Keychain access from this
        // process, so this path is sandbox-safe.
        if let token = keychainHelperReader.readToken() {
            cachedToken = token
            logger.info("Token read from Keychain helper file")
            return token
        }

        // Source 3: decrypt config.json (Claude Desktop)
        if let token = tokenFromConfigJSON() {
            cachedToken = token
            return token
        }

        // Source 4: Keychain direct - almost never works for sandboxed ad-hoc
        // signed apps (ACL blocks us) but kept as a last resort.
        if let token = keychainReader(true) {
            cachedToken = token
            logger.info("Token read from Keychain (silent) and cached in memory")
            return token
        }

        return nil
    }

    /// Try to decrypt config.json. If key is missing, attempt silent re-bootstrap.
    private func tokenFromConfigJSON() -> String? {
        guard let encrypted = configReader.readEncryptedToken() else { return nil }

        if decryptionService.hasEncryptionKey,
           let token = decryptFromConfigJSON(encrypted) {
            return token
        }

        if decryptionService.trySilentRebootstrap(),
           let token = decryptFromConfigJSON(encrypted) {
            logger.info("Token recovered via silent re-bootstrap of decryption key")
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

    func bootstrap() throws {
        if let token = keychainReader(false) {
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

    private static func defaultKeychainReader(silent: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if silent {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }

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

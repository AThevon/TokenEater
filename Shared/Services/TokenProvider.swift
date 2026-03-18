import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "TokenProvider")

final class TokenProvider: TokenProviderProtocol, @unchecked Sendable {
    private let credentialsFileReader: CredentialsFileReaderProtocol
    private let configReader: ClaudeConfigReaderProtocol
    private let decryptionService: ElectronDecryptionServiceProtocol
    private let keychainReader: KeychainTokenReader

    /// In-memory token cache — avoids hitting the Keychain on every refresh.
    /// Only cleared on 401 (token expired) via `invalidateToken()`.
    private var cachedToken: String?

    /// Closure type for reading from the Keychain. `silent` = use kSecUseAuthenticationUISkip.
    typealias KeychainTokenReader = (_ silent: Bool) -> String?

    init(
        credentialsFileReader: CredentialsFileReaderProtocol = CredentialsFileReader(),
        configReader: ClaudeConfigReaderProtocol = ClaudeConfigReader(),
        decryptionService: ElectronDecryptionServiceProtocol = ElectronDecryptionService(),
        keychainReader: KeychainTokenReader? = nil
    ) {
        self.credentialsFileReader = credentialsFileReader
        self.configReader = configReader
        self.decryptionService = decryptionService
        self.keychainReader = keychainReader ?? Self.defaultKeychainReader
    }

    var isBootstrapped: Bool { true }

    func hasTokenSource() -> Bool {
        if cachedToken != nil { return true }
        if credentialsFileReader.readToken() != nil { return true }
        if keychainReader(true) != nil { return true }
        if configReader.readEncryptedToken() != nil { return true }
        return false
    }

    /// Returns the current token, using the in-memory cache if available.
    /// The Keychain is only read when the cache is empty (app start, or after `invalidateToken()`).
    func currentToken() -> String? {
        // Fast path: cached token from a previous successful read
        if let token = cachedToken { return token }

        // Source 1: credentials file (future-proof)
        if let token = credentialsFileReader.readToken() {
            cachedToken = token
            return token
        }

        // Source 2: Keychain — silent read, ONE time (then cached)
        if let token = keychainReader(true) {
            cachedToken = token
            logger.info("Token read from Keychain and cached in memory")
            return token
        }

        // Source 3: decrypt config.json (may be stale but better than nothing)
        if decryptionService.hasEncryptionKey,
           let encrypted = configReader.readEncryptedToken(),
           let token = decryptFromConfigJSON(encrypted) {
            cachedToken = token
            return token
        }

        return nil
    }

    /// Call this after a 401 — clears the in-memory cache so the next `currentToken()`
    /// re-reads from Keychain/file to pick up a refreshed token.
    func invalidateToken() {
        cachedToken = nil
        logger.info("Token cache invalidated — next read will check Keychain")
    }

    func bootstrap() throws {
        // Interactive Keychain read — triggers macOS "Allow" dialog
        if let token = keychainReader(false) {
            cachedToken = token
            logger.info("Bootstrap succeeded via interactive Keychain read")
        }

        // Also bootstrap decryption key for config.json fallback
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

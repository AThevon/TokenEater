import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "TokenProvider")

final class TokenProvider: TokenProviderProtocol, @unchecked Sendable {
    private let credentialsFileReader: CredentialsFileReaderProtocol
    private let configReader: ClaudeConfigReaderProtocol
    private let decryptionService: ElectronDecryptionServiceProtocol
    private let keychainReader: KeychainTokenReader

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

    var isBootstrapped: Bool { true } // No bootstrap needed anymore — we read Keychain silently

    func hasTokenSource() -> Bool {
        if credentialsFileReader.readToken() != nil { return true }
        if readKeychainTokenSilently() != nil { return true }
        if configReader.readEncryptedToken() != nil { return true }
        return false
    }

    func currentToken() -> String? {
        // Source 1: credentials file (future-proof, when Anthropic writes it on macOS)
        if let token = credentialsFileReader.readToken() { return token }

        // Source 2: Keychain "Claude Code-credentials" — silent read, no UI prompt
        // This is the authoritative source. kSecUseAuthenticationUISkip means:
        // - If macOS grants access → we get the token (no dialog)
        // - If macOS denies → returns nil silently (no dialog)
        // The "Always Allow" may or may not persist (Claude Code recreates the entry ~8h),
        // but we NEVER trigger a dialog from here.
        if let token = readKeychainTokenSilently() { return token }

        // Source 3: decrypt config.json (may contain stale token, but better than nothing)
        if decryptionService.hasEncryptionKey,
           let encrypted = configReader.readEncryptedToken() {
            if let token = decryptFromConfigJSON(encrypted) { return token }
        }

        return nil
    }

    func bootstrap() throws {
        // Interactive Keychain read for "Claude Code-credentials"
        // This triggers the macOS "Allow TokenEater to access..." dialog
        let token = try readKeychainTokenInteractive()
        if token != nil {
            logger.info("Bootstrap succeeded via interactive Keychain read")
        }

        // Also bootstrap the decryption key for config.json fallback
        do {
            try decryptionService.bootstrapEncryptionKey()
            logger.info("Decryption key bootstrapped for config.json fallback")
        } catch {
            // Non-fatal — config.json is just a fallback
            logger.info("Decryption key bootstrap skipped: \(error)")
        }
    }

    // MARK: - Keychain

    private func readKeychainTokenSilently() -> String? {
        keychainReader(true)
    }

    private func readKeychainTokenInteractive() throws -> String? {
        guard let token = keychainReader(false) else {
            throw ElectronDecryptionError.keychainReadFailed(-1)
        }
        return token
    }

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
            logger.error("Config.json decryption failed: \(error)")
            return nil
        }
    }

    private static func extractToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Format 1: claudeAiOauth.accessToken
        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            return token
        }
        // Format 2: UUID-based key with "token" field
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

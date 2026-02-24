import Foundation
import Security

enum KeychainOAuthReader {
    struct OAuthCredentials {
        let accessToken: String
    }

    /// Read the Claude Code OAuth token interactively (may trigger macOS Keychain dialog).
    /// Use for onboarding, settings, and explicit user actions only.
    static func readClaudeCodeToken() -> OAuthCredentials? {
        readToken(allowUI: true)
    }

    /// Read the Claude Code OAuth token silently (never triggers a dialog).
    /// Returns nil if the Keychain item requires authentication.
    /// Use for periodic refresh and 401/403 recovery.
    static func readClaudeCodeTokenSilently() -> OAuthCredentials? {
        readToken(allowUI: false)
    }

    /// Check if the Claude Code Keychain item exists WITHOUT triggering the password dialog.
    /// Uses kSecReturnAttributes (metadata only) instead of kSecReturnData.
    static func tokenExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }

    // MARK: - Private

    private static func readToken(allowUI: Bool) -> OAuthCredentials? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        if !allowUI {
            // kSecUseAuthenticationUISkip: fail immediately if user interaction is needed
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
        else {
            return nil
        }

        return OAuthCredentials(accessToken: token)
    }
}

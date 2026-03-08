import Foundation
import Security

/// Reads OAuth tokens from the Claude Code credentials file (~/.claude/.credentials.json)
/// with silent Keychain fallback for boot/onboarding only.
/// The auto-refresh cycle never touches the Keychain to avoid popup dialogs after sleep.
final class KeychainService: KeychainServiceProtocol, @unchecked Sendable {

    private let credentialsFileReader: CredentialsFileReaderProtocol

    init(credentialsFileReader: CredentialsFileReaderProtocol = CredentialsFileReader()) {
        self.credentialsFileReader = credentialsFileReader
    }

    func readToken() -> String? {
        credentialsFileReader.readToken()
    }

    func tokenExists() -> Bool {
        if credentialsFileReader.tokenExists() { return true }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }

    func readKeychainTokenSilently() -> String? {
        // Credentials file first — no Keychain access needed
        if let token = credentialsFileReader.readToken() { return token }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]

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

        return token
    }
}

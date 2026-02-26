import Foundation
import Security

final class KeychainService: KeychainServiceProtocol, @unchecked Sendable {

    private let credentialsFileReader: CredentialsFileReaderProtocol

    init(credentialsFileReader: CredentialsFileReaderProtocol = CredentialsFileReader()) {
        self.credentialsFileReader = credentialsFileReader
    }

    /// Interactive read — may trigger macOS Keychain dialog.
    func readOAuthToken() -> String? {
        credentialsFileReader.readToken() ?? readKeychainToken(allowUI: true)
    }

    /// Silent read — never triggers a dialog. Returns nil if auth is needed.
    func readOAuthTokenSilently() -> String? {
        credentialsFileReader.readToken() ?? readKeychainToken(allowUI: false)
    }

    func tokenExists() -> Bool {
        if credentialsFileReader.tokenExists() { return true }

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

    private func readKeychainToken(allowUI: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        if !allowUI {
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

        return token
    }
}

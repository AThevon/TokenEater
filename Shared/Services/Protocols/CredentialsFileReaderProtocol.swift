import Foundation

protocol CredentialsFileReaderProtocol: Sendable {
    /// The login in `~/.claude/.credentials.json`, with its expiry when the
    /// file carries one. Claude Desktop's embedded Claude Code engine can keep
    /// this file current while the Keychain item goes stale, so the expiry is
    /// what lets `TokenProvider` prefer whichever of the two still works.
    func readCredential() -> ClaudeCredential?
    func tokenExists() -> Bool
}

extension CredentialsFileReaderProtocol {
    /// The old shape, for the call sites that only need to know whether a
    /// token exists.
    func readToken() -> String? { readCredential()?.token }
}

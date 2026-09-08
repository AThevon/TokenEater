import Foundation

final class MockCodexTokenProvider: CodexTokenProviderProtocol, @unchecked Sendable {
    var credentials: CodexCredentials?
    var stubbedAuthState: CodexAuthState = .notInstalled
    var invalidateCount = 0
    var refreshIfChangedResult = false
    var refreshIfChangedCount = 0
    /// Credentials handed out after the next `invalidate()`, so a test can model
    /// Codex refreshing the token underneath us.
    var credentialsAfterInvalidate: CodexCredentials?

    var authState: CodexAuthState { stubbedAuthState }
    var codexHomeURL: URL { URL(fileURLWithPath: "/tmp/mock-codex") }
    var authFileURL: URL { URL(fileURLWithPath: "/tmp/mock-codex/auth.json") }

    func currentCredentials() -> CodexCredentials? { credentials }

    func invalidate() {
        invalidateCount += 1
        if let credentialsAfterInvalidate {
            credentials = credentialsAfterInvalidate
            self.credentialsAfterInvalidate = nil
        }
    }

    func refreshIfChanged() -> Bool {
        refreshIfChangedCount += 1
        return refreshIfChangedResult
    }
}

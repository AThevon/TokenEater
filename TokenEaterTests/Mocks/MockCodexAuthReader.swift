import Foundation

final class MockCodexAuthReader: CodexAuthReaderProtocol, @unchecked Sendable {
    var stubbedCredentials: CodexCredentials?
    var stubbedAuthState: CodexAuthState = .notInstalled
    var readCount = 0

    var authFileURL: URL { URL(fileURLWithPath: "/tmp/mock-codex/auth.json") }
    var codexHomeURL: URL { URL(fileURLWithPath: "/tmp/mock-codex") }

    func readCredentials() -> CodexCredentials? {
        readCount += 1
        return stubbedCredentials
    }

    func authState() -> CodexAuthState { stubbedAuthState }
}

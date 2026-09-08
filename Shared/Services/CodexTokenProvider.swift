import Foundation
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "CodexTokenProvider")

/// In-memory cache over `CodexAuthReader`, mirroring `TokenProvider`'s contract
/// so both providers behave identically from a store's point of view.
///
/// Unlike the Claude provider there is no priority chain and no interactive
/// bootstrap: Codex keeps exactly one credential file and reading it never
/// prompts.
final class CodexTokenProvider: CodexTokenProviderProtocol, @unchecked Sendable {

    // MARK: - Private Properties

    private let reader: CodexAuthReaderProtocol
    private let lock = NSLock()
    private var cachedCredentials: CodexCredentials?

    // MARK: - Initializers

    init(reader: CodexAuthReaderProtocol = CodexAuthReader()) {
        self.reader = reader
    }

    // MARK: - CodexTokenProviderProtocol

    var authState: CodexAuthState { reader.authState() }

    var codexHomeURL: URL { reader.codexHomeURL }

    var authFileURL: URL { reader.authFileURL }

    func currentCredentials() -> CodexCredentials? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedCredentials { return cachedCredentials }
        let fresh = reader.readCredentials()
        cachedCredentials = fresh
        return fresh
    }

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cachedCredentials = nil
    }

    /// Returns true only on an actual change between two usable tokens. A first
    /// population and a transient read failure both return false, so a working
    /// token is never dropped because the file happened to be mid-write.
    func refreshIfChanged() -> Bool {
        guard let fresh = reader.readCredentials() else { return false }
        lock.lock()
        defer { lock.unlock() }
        let previous = cachedCredentials
        cachedCredentials = fresh
        guard let previous else { return false }
        if previous.accessToken != fresh.accessToken || previous.accountId != fresh.accountId {
            logger.info("Codex credentials changed on disk - cache refreshed")
            return true
        }
        return false
    }
}

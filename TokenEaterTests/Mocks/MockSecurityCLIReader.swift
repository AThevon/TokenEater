import Foundation

final class MockSecurityCLIReader: SecurityCLIReaderProtocol, @unchecked Sendable {
    var token: String?
    /// What `read()` reports when `token` is nil. Defaults to the ordinary
    /// "this Mac has no such item" rather than a refusal.
    var failure: KeychainReadFailure = .notFound
    var readCallCount = 0

    func read() -> Result<String, KeychainReadFailure> {
        readCallCount += 1
        if let token { return .success(token) }
        return .failure(failure)
    }
}

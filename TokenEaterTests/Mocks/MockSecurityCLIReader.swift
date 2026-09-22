import Foundation

final class MockSecurityCLIReader: SecurityCLIReaderProtocol, @unchecked Sendable {
    var token: String?
    /// What `read()` reports when `token` is nil. Defaults to the ordinary
    /// "this Mac has no such item" rather than a refusal.
    var failure: KeychainReadFailure = .notFound
    var readCallCount = 0

    /// How many items the enumeration saw. Tests set it to reproduce a
    /// shadowed service name (#268).
    var matchingItems = 1

    func read() -> KeychainRead {
        readCallCount += 1
        if let token { return .success(token, matchingItems: matchingItems) }
        return .failure(failure, matchingItems: matchingItems)
    }
}

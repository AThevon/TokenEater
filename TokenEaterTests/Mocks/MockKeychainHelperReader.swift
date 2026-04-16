import Foundation

final class MockKeychainHelperReader: KeychainHelperReaderProtocol, @unchecked Sendable {
    var token: String?
    var syncDate: Date?
    var errorMessage: String?

    func readToken() -> String? { token }
    func lastSyncAt() -> Date? { syncDate }
    func lastError() -> String? { errorMessage }
}

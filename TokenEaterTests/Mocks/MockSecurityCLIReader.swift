import Foundation

final class MockSecurityCLIReader: SecurityCLIReaderProtocol, @unchecked Sendable {
    var token: String?
    var readCallCount = 0

    func readToken() -> String? {
        readCallCount += 1
        return token
    }
}

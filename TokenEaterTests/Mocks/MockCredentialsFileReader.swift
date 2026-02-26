import Foundation

final class MockCredentialsFileReader: CredentialsFileReaderProtocol, @unchecked Sendable {
    var storedToken: String?
    var fileExists: Bool = false

    func readToken() -> String? { storedToken }
    func tokenExists() -> Bool { fileExists }
}

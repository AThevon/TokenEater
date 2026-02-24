import Foundation

final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    var storedToken: String?

    func readOAuthToken() -> String? { storedToken }
    func tokenExists() -> Bool { storedToken != nil }
}

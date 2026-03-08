import Foundation

final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    var storedToken: String?

    func readToken() -> String? { storedToken }
    func tokenExists() -> Bool { storedToken != nil }
    func readKeychainTokenSilently() -> String? { storedToken }
}

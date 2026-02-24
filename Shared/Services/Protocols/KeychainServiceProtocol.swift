import Foundation

protocol KeychainServiceProtocol: Sendable {
    func readOAuthToken() -> String?
    func tokenExists() -> Bool
}

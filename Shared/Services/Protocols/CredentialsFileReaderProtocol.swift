import Foundation

protocol CredentialsFileReaderProtocol: Sendable {
    func readToken() -> String?
    func tokenExists() -> Bool
}

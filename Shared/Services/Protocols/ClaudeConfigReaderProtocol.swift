import Foundation

protocol ClaudeConfigReaderProtocol: Sendable {
    func readEncryptedToken() -> String?
}

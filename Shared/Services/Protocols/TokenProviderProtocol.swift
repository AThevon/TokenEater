import Foundation

protocol TokenProviderProtocol: Sendable {
    func currentToken() -> String?
    var isBootstrapped: Bool { get }
    func bootstrap() throws
}

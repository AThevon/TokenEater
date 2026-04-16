import Foundation

protocol SignatureVerifierProtocol: Sendable {
    func verify(data: Data, base64Signature: String, base64PublicKey: String) -> Bool
}

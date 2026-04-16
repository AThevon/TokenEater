import Foundation
import CryptoKit

final class SignatureVerifier: SignatureVerifierProtocol {
    func verify(data: Data, base64Signature: String, base64PublicKey: String) -> Bool {
        guard !base64Signature.isEmpty, !base64PublicKey.isEmpty else { return false }
        guard let sigData = Data(base64Encoded: base64Signature),
              let keyData = Data(base64Encoded: base64PublicKey),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return false }
        return publicKey.isValidSignature(sigData, for: data)
    }
}

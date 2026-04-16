import Foundation

final class MockSignatureVerifier: SignatureVerifierProtocol, @unchecked Sendable {
    var verifyResult: Bool = true
    private(set) var verifyCallCount: Int = 0
    private(set) var lastSignature: String?
    private(set) var lastPublicKey: String?
    private(set) var lastDataSize: Int?

    func verify(data: Data, base64Signature: String, base64PublicKey: String) -> Bool {
        verifyCallCount += 1
        lastSignature = base64Signature
        lastPublicKey = base64PublicKey
        lastDataSize = data.count
        return verifyResult
    }
}

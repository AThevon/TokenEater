import Testing
import Foundation
import CryptoKit

@Suite("SignatureVerifier")
struct SignatureVerifierTests {
    private struct Keypair {
        let privateKey: Curve25519.Signing.PrivateKey
        let publicKeyBase64: String

        init() {
            self.privateKey = Curve25519.Signing.PrivateKey()
            self.publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        }

        func sign(_ data: Data) -> String {
            let sig = try! privateKey.signature(for: data)
            return sig.base64EncodedString()
        }
    }

    @Test("accepts a valid signature")
    func acceptsValidSignature() {
        let keypair = Keypair()
        let data = Data("hello world".utf8)
        let signature = keypair.sign(data)

        let verifier = SignatureVerifier()
        #expect(verifier.verify(data: data, base64Signature: signature, base64PublicKey: keypair.publicKeyBase64))
    }

    @Test("rejects a signature made with a different key")
    func rejectsSignatureFromDifferentKey() {
        let attacker = Keypair()
        let trusted = Keypair()
        let data = Data("hello world".utf8)
        let attackerSignature = attacker.sign(data)

        let verifier = SignatureVerifier()
        #expect(!verifier.verify(
            data: data,
            base64Signature: attackerSignature,
            base64PublicKey: trusted.publicKeyBase64
        ))
    }

    @Test("rejects a signature on different data")
    func rejectsSignatureOnDifferentData() {
        let keypair = Keypair()
        let originalData = Data("hello".utf8)
        let signature = keypair.sign(originalData)
        let tamperedData = Data("hellp".utf8)

        let verifier = SignatureVerifier()
        #expect(!verifier.verify(
            data: tamperedData,
            base64Signature: signature,
            base64PublicKey: keypair.publicKeyBase64
        ))
    }

    @Test("rejects malformed base64 signature")
    func rejectsMalformedBase64Signature() {
        let keypair = Keypair()
        let data = Data("hello".utf8)

        let verifier = SignatureVerifier()
        #expect(!verifier.verify(
            data: data,
            base64Signature: "not-valid-base64!!!",
            base64PublicKey: keypair.publicKeyBase64
        ))
    }

    @Test("rejects malformed base64 public key")
    func rejectsMalformedBase64PublicKey() {
        let keypair = Keypair()
        let data = Data("hello".utf8)
        let signature = keypair.sign(data)

        let verifier = SignatureVerifier()
        #expect(!verifier.verify(
            data: data,
            base64Signature: signature,
            base64PublicKey: "not-valid-base64!!!"
        ))
    }

    @Test("rejects empty signature")
    func rejectsEmptySignature() {
        let keypair = Keypair()
        let data = Data("hello".utf8)

        let verifier = SignatureVerifier()
        #expect(!verifier.verify(
            data: data,
            base64Signature: "",
            base64PublicKey: keypair.publicKeyBase64
        ))
    }

    @Test("rejects empty public key")
    func rejectsEmptyPublicKey() {
        let keypair = Keypair()
        let data = Data("hello".utf8)
        let signature = keypair.sign(data)

        let verifier = SignatureVerifier()
        #expect(!verifier.verify(
            data: data,
            base64Signature: signature,
            base64PublicKey: ""
        ))
    }

    @Test("rejects public key with wrong length")
    func rejectsShortPublicKey() {
        let keypair = Keypair()
        let data = Data("hello".utf8)
        let signature = keypair.sign(data)
        // Valid base64, but decodes to 3 bytes not 32.
        let shortKey = Data([0x01, 0x02, 0x03]).base64EncodedString()

        let verifier = SignatureVerifier()
        #expect(!verifier.verify(
            data: data,
            base64Signature: signature,
            base64PublicKey: shortKey
        ))
    }

    @Test("verifies large payload (simulated DMG)")
    func verifiesLargePayload() {
        let keypair = Keypair()
        // ~2 MB of random-ish bytes, matching a real TokenEater DMG size range.
        var rng = SystemRandomNumberGenerator()
        let data = Data((0..<(2 * 1024 * 1024)).map { _ in UInt8.random(in: 0...255, using: &rng) })
        let signature = keypair.sign(data)

        let verifier = SignatureVerifier()
        #expect(verifier.verify(
            data: data,
            base64Signature: signature,
            base64PublicKey: keypair.publicKeyBase64
        ))
    }
}

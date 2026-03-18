import Testing
import Foundation

@Suite("ElectronDecryptionService")
struct ElectronDecryptionServiceTests {

    @Test("rejects data without v10 prefix")
    func rejectsWithoutV10Prefix() {
        let sut = ElectronDecryptionService()
        let key = ElectronDecryptionService.deriveKey(from: "testpassword")
        sut.setDerivedKeyForTesting(key)

        // Valid base64 but no v10 prefix
        let badData = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                            0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
                            0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17])
        let base64 = badData.base64EncodedString()

        #expect(throws: ElectronDecryptionError.missingV10Prefix) {
            try sut.decrypt(base64)
        }
    }

    @Test("rejects empty base64")
    func rejectsEmptyBase64() {
        let sut = ElectronDecryptionService()
        let key = ElectronDecryptionService.deriveKey(from: "testpassword")
        sut.setDerivedKeyForTesting(key)

        #expect(throws: ElectronDecryptionError.missingV10Prefix) {
            try sut.decrypt("")
        }
    }

    @Test("rejects invalid base64")
    func rejectsInvalidBase64() {
        let sut = ElectronDecryptionService()
        let key = ElectronDecryptionService.deriveKey(from: "testpassword")
        sut.setDerivedKeyForTesting(key)

        #expect(throws: ElectronDecryptionError.invalidBase64) {
            try sut.decrypt("not!valid!base64!!!")
        }
    }

    @Test("hasEncryptionKey is false before bootstrap")
    func hasEncryptionKeyFalseBeforeBootstrap() {
        let sut = ElectronDecryptionService()
        // No key set, no cached keychain key expected in test environment
        #expect(sut.hasEncryptionKey == false)
    }

    @Test("clearCachedKey removes the key")
    func clearCachedKeyRemovesKey() {
        let sut = ElectronDecryptionService()
        let key = ElectronDecryptionService.deriveKey(from: "testpassword")
        sut.setDerivedKeyForTesting(key)
        #expect(sut.hasEncryptionKey == true)

        sut.clearCachedKey()
        #expect(sut.hasEncryptionKey == false)
    }

    @Test("PBKDF2 key derivation produces 16 bytes")
    func keyDerivationProduces16Bytes() {
        let key = ElectronDecryptionService.deriveKey(from: "testpassword")
        #expect(key.count == 16)
    }

    @Test("PBKDF2 key derivation is deterministic")
    func keyDerivationIsDeterministic() {
        let key1 = ElectronDecryptionService.deriveKey(from: "same-password")
        let key2 = ElectronDecryptionService.deriveKey(from: "same-password")
        #expect(key1 == key2)
    }

    @Test("PBKDF2 key derivation differs for different passwords")
    func keyDerivationDiffersForDifferentPasswords() {
        let key1 = ElectronDecryptionService.deriveKey(from: "password-a")
        let key2 = ElectronDecryptionService.deriveKey(from: "password-b")
        #expect(key1 != key2)
    }

    @Test("full encrypt-then-decrypt round trip")
    func encryptThenDecryptRoundTrip() throws {
        let sut = ElectronDecryptionService()
        let password = "test-electron-password"
        let key = ElectronDecryptionService.deriveKey(from: password)
        sut.setDerivedKeyForTesting(key)

        let plaintext = Data("hello world, this is a secret token value!".utf8)
        let encrypted = try ElectronDecryptionService.encryptForTesting(plaintext: plaintext, key: key)
        let base64 = encrypted.base64EncodedString()

        let decrypted = try sut.decrypt(base64)
        #expect(decrypted == plaintext)
    }

    @Test("round trip with empty plaintext")
    func roundTripEmptyPlaintext() throws {
        let sut = ElectronDecryptionService()
        let key = ElectronDecryptionService.deriveKey(from: "pw")
        sut.setDerivedKeyForTesting(key)

        let plaintext = Data()
        let encrypted = try ElectronDecryptionService.encryptForTesting(plaintext: plaintext, key: key)
        let decrypted = try sut.decrypt(encrypted.base64EncodedString())
        #expect(decrypted == plaintext)
    }

    @Test("decrypt fails without encryption key set")
    func decryptFailsWithoutKey() {
        let sut = ElectronDecryptionService()
        // v10 prefix + 16 bytes of fake ciphertext
        var data = Data([0x76, 0x31, 0x30])
        data.append(Data(repeating: 0xAA, count: 16))
        let base64 = data.base64EncodedString()

        #expect(throws: ElectronDecryptionError.keyDerivationFailed) {
            try sut.decrypt(base64)
        }
    }
}

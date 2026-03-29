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

    @Test("hasEncryptionKey is false after clearCachedKey")
    func hasEncryptionKeyFalseAfterClear() {
        let sut = ElectronDecryptionService()
        sut.clearCachedKey()
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

    @Test("file-based key cache: save then load round trip")
    func fileCacheRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keyFile = tempDir.appendingPathComponent("decryption.key")
        let key = ElectronDecryptionService.deriveKey(from: "test-password")

        ElectronDecryptionService.saveKeyToFile(key, at: keyFile)
        let loaded = ElectronDecryptionService.loadKeyFromFile(at: keyFile)

        #expect(loaded == key)
    }

    @Test("file-based key cache: returns nil when file missing")
    func fileCacheReturnsNilWhenMissing() {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString)")
            .appendingPathComponent("decryption.key")
        let loaded = ElectronDecryptionService.loadKeyFromFile(at: bogus)
        #expect(loaded == nil)
    }

    @Test("file-based key cache: returns nil when file has wrong version byte")
    func fileCacheRejectsWrongVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keyFile = tempDir.appendingPathComponent("decryption.key")
        var badPayload = Data([0xFF]) // wrong version
        badPayload.append(Data(repeating: 0xAA, count: 16))
        try badPayload.write(to: keyFile)

        let loaded = ElectronDecryptionService.loadKeyFromFile(at: keyFile)
        #expect(loaded == nil)
    }

    @Test("trySilentRebootstrap returns a Bool and updates hasEncryptionKey accordingly")
    func trySilentRebootstrapReturnsConsistentState() {
        let sut = ElectronDecryptionService()
        sut.clearCachedKey()
        #expect(sut.hasEncryptionKey == false)

        let result = sut.trySilentRebootstrap()
        // Result depends on whether "Claude Safe Storage" keychain item exists.
        // On CI: false (no Electron keychain). On dev machine with Claude: true.
        // Either way, hasEncryptionKey must match the return value.
        #expect(sut.hasEncryptionKey == result)
    }

    @Test("migrateKeyFromKeychainToFile: saves and loads correctly via file round-trip")
    func migrateKeyFromKeychainToFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keyFile = tempDir.appendingPathComponent("decryption.key")
        let key = ElectronDecryptionService.deriveKey(from: "migrate-test")

        // File doesn't exist yet
        #expect(ElectronDecryptionService.loadKeyFromFile(at: keyFile) == nil)

        // Simulate migration: save to file
        ElectronDecryptionService.saveKeyToFile(key, at: keyFile)

        // File now has the key
        #expect(ElectronDecryptionService.loadKeyFromFile(at: keyFile) == key)
    }

    @Test("file-based key cache: returns nil when file too short")
    func fileCacheRejectsTooShort() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keyFile = tempDir.appendingPathComponent("decryption.key")
        try Data([0x01, 0xAA]).write(to: keyFile) // version + only 1 byte

        let loaded = ElectronDecryptionService.loadKeyFromFile(at: keyFile)
        #expect(loaded == nil)
    }
}

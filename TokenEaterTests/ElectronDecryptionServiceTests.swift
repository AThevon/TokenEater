import Testing
import Foundation

@Suite("ElectronDecryptionService")
struct ElectronDecryptionServiceTests {

    private enum StubError: Error { case noPassword }

    /// A service pointed at a throwaway temp key file (so the real
    /// `~/Library/Application Support/com.tokeneater.shared/decryption.key` is
    /// never read, written, or deleted) with an optional stub password source
    /// (so the real "Claude Safe Storage" Keychain item is never read). Call
    /// `cleanup()` via `defer` to remove the temp directory.
    ///
    /// Before this seam existed, constructing a bare `ElectronDecryptionService()`
    /// and calling `clearCachedKey()` / `trySilentRebootstrap()` in tests hit the
    /// live paths: it deleted the real cached key and, on any machine with Claude
    /// Desktop installed, silently read the Electron safeStorage Keychain item.
    private func makeSUT(
        passwordReader: (@Sendable (_ silent: Bool) throws -> String)? = nil
    ) -> (sut: ElectronDecryptionService, keyFile: URL, cleanup: () -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keyFile = dir.appendingPathComponent("decryption.key")
        let sut = ElectronDecryptionService(keyFileURL: keyFile, passwordReader: passwordReader)
        return (sut, keyFile, { try? FileManager.default.removeItem(at: dir) })
    }

    @Test("rejects data without v10 prefix")
    func rejectsWithoutV10Prefix() {
        let (sut, _, cleanup) = makeSUT(); defer { cleanup() }
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
        let (sut, _, cleanup) = makeSUT(); defer { cleanup() }
        let key = ElectronDecryptionService.deriveKey(from: "testpassword")
        sut.setDerivedKeyForTesting(key)

        #expect(throws: ElectronDecryptionError.missingV10Prefix) {
            try sut.decrypt("")
        }
    }

    @Test("rejects invalid base64")
    func rejectsInvalidBase64() {
        let (sut, _, cleanup) = makeSUT(); defer { cleanup() }
        let key = ElectronDecryptionService.deriveKey(from: "testpassword")
        sut.setDerivedKeyForTesting(key)

        #expect(throws: ElectronDecryptionError.invalidBase64) {
            try sut.decrypt("not!valid!base64!!!")
        }
    }

    @Test("hasEncryptionKey is false after clearCachedKey")
    func hasEncryptionKeyFalseAfterClear() {
        let (sut, _, cleanup) = makeSUT(); defer { cleanup() }
        sut.clearCachedKey()
        #expect(sut.hasEncryptionKey == false)
    }

    @Test("clearCachedKey removes the key")
    func clearCachedKeyRemovesKey() {
        let (sut, _, cleanup) = makeSUT(); defer { cleanup() }
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
        let (sut, _, cleanup) = makeSUT(); defer { cleanup() }
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
        let (sut, _, cleanup) = makeSUT(); defer { cleanup() }
        let key = ElectronDecryptionService.deriveKey(from: "pw")
        sut.setDerivedKeyForTesting(key)

        let plaintext = Data()
        let encrypted = try ElectronDecryptionService.encryptForTesting(plaintext: plaintext, key: key)
        let decrypted = try sut.decrypt(encrypted.base64EncodedString())
        #expect(decrypted == plaintext)
    }

    @Test("decrypt fails without encryption key set")
    func decryptFailsWithoutKey() {
        let (sut, _, cleanup) = makeSUT(); defer { cleanup() }
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

    @Test("trySilentRebootstrap succeeds and caches the key when a password is available")
    func trySilentRebootstrapSucceedsWithPassword() {
        // Stub the password source so we never read the real Keychain, and point
        // the cache at a temp file so we never touch the real decryption.key.
        let (sut, keyFile, cleanup) = makeSUT(passwordReader: { _ in "electron-password" })
        defer { cleanup() }
        sut.clearCachedKey()
        #expect(sut.hasEncryptionKey == false)

        let result = sut.trySilentRebootstrap()

        #expect(result == true)
        #expect(sut.hasEncryptionKey == true)
        // The derived key was cached to the temp file, never the real one.
        #expect(ElectronDecryptionService.loadKeyFromFile(at: keyFile) != nil)
    }

    @Test("trySilentRebootstrap fails and stays keyless when no password is available")
    func trySilentRebootstrapFailsWithoutPassword() {
        let (sut, keyFile, cleanup) = makeSUT(passwordReader: { _ in throw StubError.noPassword })
        defer { cleanup() }
        sut.clearCachedKey()

        let result = sut.trySilentRebootstrap()

        #expect(result == false)
        #expect(sut.hasEncryptionKey == false)
        #expect(ElectronDecryptionService.loadKeyFromFile(at: keyFile) == nil)
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

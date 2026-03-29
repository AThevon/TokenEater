import Foundation
import CommonCrypto
import Security

enum ElectronDecryptionError: Error, Equatable, CustomStringConvertible {
    case invalidBase64
    case missingV10Prefix
    case ciphertextTooShort
    case decryptionFailed(CCCryptorStatus)
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case keychainPasswordEmpty
    case keyDerivationFailed

    var description: String {
        switch self {
        case .invalidBase64: return "Invalid base64 input"
        case .missingV10Prefix: return "Encrypted data missing v10 prefix"
        case .ciphertextTooShort: return "Ciphertext too short for AES-128-CBC"
        case .decryptionFailed(let status): return "AES decryption failed (status \(status))"
        case .keychainReadFailed(let status): return "Keychain read failed (status \(status))"
        case .keychainWriteFailed(let status): return "Keychain write failed (status \(status))"
        case .keychainPasswordEmpty: return "Keychain password is empty"
        case .keyDerivationFailed: return "PBKDF2 key derivation failed"
        }
    }
}

final class ElectronDecryptionService: ElectronDecryptionServiceProtocol, @unchecked Sendable {

    // MARK: - Constants

    private static let v10Prefix = Data([0x76, 0x31, 0x30]) // "v10"
    private static let salt = "saltysalt"
    private static let pbkdf2Iterations: UInt32 = 1003
    private static let keyLength = 16 // AES-128
    private static let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128) // 16 spaces

    // Electron source Keychain
    private static let electronService = "Claude Safe Storage"
    private static let electronAccount = "Claude Key"

    // TokenEater cached key Keychain
    private static let cacheService = "TokenEater"
    private static let cacheAccount = "decryption-key"
    private static let cacheVersionByte: UInt8 = 0x01

    // MARK: - State

    private var derivedKey: Data?

    // MARK: - Protocol

    var hasEncryptionKey: Bool { derivedKey != nil }

    init() {
        derivedKey = Self.loadKeyFromFile()
    }

    func decrypt(_ encryptedBase64: String) throws -> Data {
        guard let raw = Data(base64Encoded: encryptedBase64) else {
            throw ElectronDecryptionError.invalidBase64
        }

        guard raw.count >= Self.v10Prefix.count,
              raw.prefix(Self.v10Prefix.count) == Self.v10Prefix else {
            throw ElectronDecryptionError.missingV10Prefix
        }

        let ciphertext = raw.dropFirst(Self.v10Prefix.count)
        guard ciphertext.count >= kCCBlockSizeAES128 else {
            throw ElectronDecryptionError.ciphertextTooShort
        }

        guard let key = derivedKey else {
            throw ElectronDecryptionError.keyDerivationFailed
        }

        return try Self.aesDecrypt(ciphertext: Data(ciphertext), key: key)
    }

    func bootstrapEncryptionKey() throws {
        // Interactive Keychain read — prompts user for permission
        let password = try Self.readElectronPassword(silent: false)
        let key = Self.deriveKey(from: password)
        Self.saveKeyToFile(key)
        derivedKey = key
    }

    func clearCachedKey() {
        derivedKey = nil
        Self.deleteKeyFile()
    }

    func trySilentRebootstrap() -> Bool {
        guard let password = try? Self.readElectronPassword(silent: true) else {
            return false
        }
        let key = Self.deriveKey(from: password)
        Self.saveKeyToFile(key)
        derivedKey = key
        return true
    }

    // MARK: - Key Derivation (internal for testing)

    static func deriveKey(from password: String) -> Data {
        let passwordData = Array(password.utf8)
        let saltData = Array(Self.salt.utf8)
        var derivedBytes = [UInt8](repeating: 0, count: keyLength)

        CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordData,
            passwordData.count,
            saltData,
            saltData.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            pbkdf2Iterations,
            &derivedBytes,
            keyLength
        )

        return Data(derivedBytes)
    }

    // MARK: - AES

    private static func aesDecrypt(ciphertext: Data, key: Data) throws -> Data {
        var outLength = 0
        var outBuffer = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)

        let status = ciphertext.withUnsafeBytes { ciphertextPtr in
            key.withUnsafeBytes { keyPtr in
                iv.withUnsafeBytes { ivPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, keyLength,
                        ivPtr.baseAddress,
                        ciphertextPtr.baseAddress, ciphertext.count,
                        &outBuffer, outBuffer.count,
                        &outLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw ElectronDecryptionError.decryptionFailed(status)
        }

        return Data(outBuffer.prefix(outLength))
    }

    static func aesEncrypt(plaintext: Data, key: Data) throws -> Data {
        var outLength = 0
        var outBuffer = [UInt8](repeating: 0, count: plaintext.count + kCCBlockSizeAES128)

        let status = plaintext.withUnsafeBytes { plaintextPtr in
            key.withUnsafeBytes { keyPtr in
                iv.withUnsafeBytes { ivPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, keyLength,
                        ivPtr.baseAddress,
                        plaintextPtr.baseAddress, plaintext.count,
                        &outBuffer, outBuffer.count,
                        &outLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw ElectronDecryptionError.decryptionFailed(status)
        }

        return Data(outBuffer.prefix(outLength))
    }

    // MARK: - Electron Keychain

    private static func readElectronPassword(silent: Bool) throws -> String {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: electronService,
            kSecAttrAccount as String: electronAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if silent {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw ElectronDecryptionError.keychainReadFailed(status)
        }

        guard let password = String(data: data, encoding: .utf8), !password.isEmpty else {
            throw ElectronDecryptionError.keychainPasswordEmpty
        }

        return password
    }

    // MARK: - File-Based Key Cache

    private static let keyFileName = "decryption.key"

    private static var keyFileURL: URL {
        let home: String
        if let pw = getpwuid(getuid()) {
            home = String(cString: pw.pointee.pw_dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("com.tokeneater.shared")
            .appendingPathComponent(keyFileName)
    }

    static func loadKeyFromFile(at url: URL? = nil) -> Data? {
        let fileURL = url ?? keyFileURL
        guard let data = try? Data(contentsOf: fileURL),
              data.count > 1,
              data.first == cacheVersionByte else {
            return nil
        }
        let key = data.dropFirst()
        guard key.count == keyLength else { return nil }
        return Data(key)
    }

    static func saveKeyToFile(_ key: Data, at url: URL? = nil) {
        let fileURL = url ?? keyFileURL
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var payload = Data([cacheVersionByte])
        payload.append(key)
        try? payload.write(to: fileURL, options: [.atomic, .completeFileProtection])

        // Set file permissions to 0600 (owner read-write only)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    static func deleteKeyFile(at url: URL? = nil) {
        let fileURL = url ?? keyFileURL
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Migration (Keychain → File, remove after v5.x)

    private static func loadCachedKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cacheService,
            kSecAttrAccount as String: cacheAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              data.count > 1,
              data.first == cacheVersionByte else {
            return nil
        }

        return data.dropFirst() // strip version byte
    }

    private static func deleteCachedKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: cacheService,
            kSecAttrAccount as String: cacheAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Test Helpers

    #if DEBUG
    func setDerivedKeyForTesting(_ key: Data) {
        derivedKey = key
    }

    static func encryptForTesting(plaintext: Data, key: Data) throws -> Data {
        let ciphertext = try aesEncrypt(plaintext: plaintext, key: key)
        var result = v10Prefix
        result.append(ciphertext)
        return result
    }
    #endif
}

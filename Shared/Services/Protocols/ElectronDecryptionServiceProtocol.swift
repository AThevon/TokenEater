import Foundation

protocol ElectronDecryptionServiceProtocol: Sendable {
    func decrypt(_ encryptedBase64: String) throws -> Data
    var hasEncryptionKey: Bool { get }
    func bootstrapEncryptionKey() throws
    func clearCachedKey()

    /// Attempt to re-derive the key from Electron's "Claude Safe Storage"
    /// Keychain item. Despite the name it is not guaranteed silent:
    /// `kSecUseAuthenticationUISkip` does not suppress the ACL prompt, so
    /// callers must not run it on a timer. Returns true if successful.
    func trySilentRebootstrap() -> Bool
}

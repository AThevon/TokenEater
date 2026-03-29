import Foundation

protocol ElectronDecryptionServiceProtocol: Sendable {
    func decrypt(_ encryptedBase64: String) throws -> Data
    var hasEncryptionKey: Bool { get }
    func bootstrapEncryptionKey() throws
    func clearCachedKey()

    /// Attempt to re-derive the key by reading Electron's keychain silently (no popup).
    /// Returns true if successful.
    func trySilentRebootstrap() -> Bool
}

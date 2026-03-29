import Foundation

final class MockElectronDecryptionService: ElectronDecryptionServiceProtocol, @unchecked Sendable {
    var decryptedData: Data?
    var decryptError: Error?
    var _hasEncryptionKey: Bool = false
    var bootstrapError: Error?
    var bootstrapCallCount = 0
    var decryptCallCount = 0

    var hasEncryptionKey: Bool { _hasEncryptionKey }

    func decrypt(_ encryptedBase64: String) throws -> Data {
        decryptCallCount += 1
        if let error = decryptError { throw error }
        return decryptedData ?? Data()
    }

    func bootstrapEncryptionKey() throws {
        bootstrapCallCount += 1
        if let error = bootstrapError { throw error }
        _hasEncryptionKey = true
    }

    func clearCachedKey() {
        _hasEncryptionKey = false
    }

    var silentRebootstrapResult: Bool = false
    var silentRebootstrapCallCount = 0

    func trySilentRebootstrap() -> Bool {
        silentRebootstrapCallCount += 1
        if silentRebootstrapResult { _hasEncryptionKey = true }
        return silentRebootstrapResult
    }
}

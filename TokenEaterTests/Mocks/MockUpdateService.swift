import Foundation

final class MockUpdateService: UpdateServiceProtocol {
    var checkResult: AppcastItem?
    var checkError: Error?
    var checkForUpdateCalled = false

    var downloadResult: URL = URL(fileURLWithPath: "/tmp/test.dmg")
    var downloadError: Error?
    var downloadCalled = false

    func checkForUpdate() async throws -> AppcastItem? {
        checkForUpdateCalled = true
        if let error = checkError { throw error }
        return checkResult
    }

    func downloadUpdate(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        downloadCalled = true
        progress(1.0)
        if let error = downloadError { throw error }
        return downloadResult
    }
}

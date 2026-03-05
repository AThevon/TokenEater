import Foundation

final class MockUpdateService: UpdateServiceProtocol {
    var checkForUpdatesCalled = false
    var canCheckResult = true

    func checkForUpdates() { checkForUpdatesCalled = true }
    var canCheckForUpdates: Bool { canCheckResult }
}

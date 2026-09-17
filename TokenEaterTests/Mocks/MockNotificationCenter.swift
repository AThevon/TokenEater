import Foundation
import UserNotifications

final class MockNotificationCenter: NotificationCenterProtocol {
    private(set) var addedIDs: [String] = []
    /// Kept whole so a test can assert on what the banner will actually say,
    /// not only that something fired.
    private(set) var added: [UNNotificationRequest] = []
    private(set) var removedIDs: [String] = []
    var stubbedStatus: UNAuthorizationStatus = .notDetermined
    var requestAuthorizationCalled = false

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {}
    func requestAuthorization() { requestAuthorizationCalled = true }
    func authorizationStatus() async -> UNAuthorizationStatus { stubbedStatus }
    func add(_ request: UNNotificationRequest) {
        addedIDs.append(request.identifier)
        added.append(request)
    }

    /// The content of the last notification whose identifier matches.
    func content(for id: String) -> UNNotificationContent? {
        added.last { $0.identifier == id }?.content
    }
    func removePending(identifiers: [String]) { removedIDs.append(contentsOf: identifiers) }
}

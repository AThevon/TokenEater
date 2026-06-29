import Foundation
import UserNotifications

final class MockNotificationCenter: NotificationCenterProtocol {
    private(set) var addedIDs: [String] = []
    private(set) var removedIDs: [String] = []
    var stubbedStatus: UNAuthorizationStatus = .notDetermined
    var requestAuthorizationCalled = false

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate?) {}
    func requestAuthorization() { requestAuthorizationCalled = true }
    func authorizationStatus() async -> UNAuthorizationStatus { stubbedStatus }
    func add(_ request: UNNotificationRequest) { addedIDs.append(request.identifier) }
    func removePending(identifiers: [String]) { removedIDs.append(contentsOf: identifiers) }
}

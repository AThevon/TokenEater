import Foundation
import UserNotifications

/// Minimal seam over UNUserNotificationCenter: only the calls NotificationService
/// actually makes, so a mock can assert delivered ids without a real center.
protocol NotificationCenterProtocol {
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate?)
    func requestAuthorization()
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest)
    func removePending(identifiers: [String])
}

final class LiveNotificationCenter: NotificationCenterProtocol {
    private let center = UNUserNotificationCenter.current()
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate?) { center.delegate = delegate }
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
    func add(_ request: UNNotificationRequest) { center.add(request) }
    func removePending(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

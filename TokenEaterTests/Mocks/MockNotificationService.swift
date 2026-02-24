import Foundation
import UserNotifications

final class MockNotificationService: NotificationServiceProtocol {
    var permissionRequested = false
    var lastThresholdCheck: (fiveHour: Int, sevenDay: Int, sonnet: Int)?
    var stubbedAuthStatus: UNAuthorizationStatus = .notDetermined
    var testSent = false

    func setupDelegate() {}
    func requestPermission() { permissionRequested = true }
    func checkAuthorizationStatus() async -> UNAuthorizationStatus { stubbedAuthStatus }
    func sendTest() { testSent = true }
    func checkThresholds(fiveHour: Int, sevenDay: Int, sonnet: Int, thresholds: UsageThresholds) {
        lastThresholdCheck = (fiveHour, sevenDay, sonnet)
    }
}

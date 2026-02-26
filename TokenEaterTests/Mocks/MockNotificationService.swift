import Foundation
import UserNotifications

final class MockNotificationService: NotificationServiceProtocol {
    var permissionRequested = false
    var lastThresholdCheck: (fiveHour: MetricSnapshot, sevenDay: MetricSnapshot, sonnet: MetricSnapshot, pacingZone: PacingZone?)?
    var stubbedAuthStatus: UNAuthorizationStatus = .notDetermined
    var testSent = false

    func setupDelegate() {}
    func requestPermission() { permissionRequested = true }
    func checkAuthorizationStatus() async -> UNAuthorizationStatus { stubbedAuthStatus }
    func sendTest() { testSent = true }
    func checkThresholds(
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        pacingZone: PacingZone?,
        thresholds: UsageThresholds
    ) {
        lastThresholdCheck = (fiveHour, sevenDay, sonnet, pacingZone)
    }
}

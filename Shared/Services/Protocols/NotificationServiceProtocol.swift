import Foundation
import UserNotifications

protocol NotificationServiceProtocol {
    func setupDelegate()
    func requestPermission()
    func checkAuthorizationStatus() async -> UNAuthorizationStatus
    func sendTest()
    func checkThresholds(fiveHour: Int, sevenDay: Int, sonnet: Int, thresholds: UsageThresholds)
}

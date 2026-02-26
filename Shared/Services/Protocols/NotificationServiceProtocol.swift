import Foundation
import UserNotifications

struct MetricSnapshot {
    let pct: Int
    let resetsAt: Date?
}

protocol NotificationServiceProtocol {
    func setupDelegate()
    func requestPermission()
    func checkAuthorizationStatus() async -> UNAuthorizationStatus
    func sendTest()
    func checkThresholds(
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        pacingZone: PacingZone?,
        thresholds: UsageThresholds
    )
}

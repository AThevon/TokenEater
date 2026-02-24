import Foundation
import UserNotifications

final class NotificationService: NotificationServiceProtocol {
    private let center = UNUserNotificationCenter.current()

    func setupDelegate() {
        center.delegate = NotificationDelegate.shared
    }

    func requestPermission() {
        setupDelegate()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "TokenEater"
        content.body = String(localized: "notif.test.body")
        content.sound = .default
        send(id: "test_\(Date().timeIntervalSince1970)", content: content)
    }

    func checkThresholds(fiveHour: Int, sevenDay: Int, sonnet: Int, thresholds: UsageThresholds) {
        check(metric: "fiveHour", label: String(localized: "metric.session"), pct: fiveHour, thresholds: thresholds)
        check(metric: "sevenDay", label: String(localized: "metric.weekly"), pct: sevenDay, thresholds: thresholds)
        check(metric: "sonnet", label: String(localized: "metric.sonnet"), pct: sonnet, thresholds: thresholds)
    }

    private func check(metric: String, label: String, pct: Int, thresholds: UsageThresholds) {
        let key = "lastLevel_\(metric)"
        let previousRaw = UserDefaults.standard.integer(forKey: key)
        let previous = UsageLevel(rawValue: previousRaw) ?? .green
        let current = UsageLevel.from(pct: pct, thresholds: thresholds)

        guard current != previous else { return }
        UserDefaults.standard.set(current.rawValue, forKey: key)

        if current > previous {
            notifyEscalation(metric: metric, label: label, pct: pct, level: current, thresholds: thresholds)
        } else if current == .green && previous > .green {
            notifyRecovery(metric: metric, label: label, pct: pct)
        }
    }

    private func notifyEscalation(metric: String, label: String, pct: Int, level: UsageLevel, thresholds: UsageThresholds) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch level {
        case .orange:
            content.title = "\u{26a0}\u{fe0f} \(label) — \(pct)%"
            content.body = String(format: String(localized: "notif.orange.body"), thresholds.warningPercent)
        case .red:
            content.title = "\u{1f534} \(label) — \(pct)%"
            content.body = String(localized: "notif.red.body")
        case .green:
            return
        }

        send(id: "escalation_\(metric)", content: content)
    }

    private func notifyRecovery(metric: String, label: String, pct: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\u{1f7e2} \(label) — \(pct)%"
        content.body = String(localized: "notif.green.body")
        content.sound = .default
        send(id: "recovery_\(metric)", content: content)
    }

    private func send(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }
}

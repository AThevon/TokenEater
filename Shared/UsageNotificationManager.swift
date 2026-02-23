import UserNotifications
import Foundation

enum UsageLevel: Int, Comparable {
    case green = 0   // < 60%
    case orange = 1  // 60-84%
    case red = 2     // >= 85%

    static func < (lhs: UsageLevel, rhs: UsageLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(pct: Int, thresholds: UsageThresholds = .default) -> UsageLevel {
        if pct >= thresholds.criticalPercent { return .red }
        if pct >= thresholds.warningPercent { return .orange }
        return .green
    }
}

/// Allows notifications to display as banners even when the app is in the foreground.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum UsageNotificationManager {
    private static let center = UNUserNotificationCenter.current()

    static func requestPermission() {
        center.delegate = NotificationDelegate.shared
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    static func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "TokenEater"
        content.body = String(localized: "notif.test.body")
        content.sound = .default
        send(id: "test_\(Date().timeIntervalSince1970)", content: content)
    }

    static func checkThresholds(fiveHour: Int, sevenDay: Int, sonnet: Int, thresholds: UsageThresholds = .default) {
        check(metric: "fiveHour", label: String(localized: "metric.session"), pct: fiveHour, thresholds: thresholds)
        check(metric: "sevenDay", label: String(localized: "metric.weekly"), pct: sevenDay, thresholds: thresholds)
        check(metric: "sonnet", label: String(localized: "metric.sonnet"), pct: sonnet, thresholds: thresholds)
    }

    private static func check(metric: String, label: String, pct: Int, thresholds: UsageThresholds) {
        let key = "lastLevel_\(metric)"
        let previousRaw = UserDefaults.standard.integer(forKey: key)
        let previous = UsageLevel(rawValue: previousRaw) ?? .green
        let current = UsageLevel.from(pct: pct, thresholds: thresholds)

        // Only notify on transitions
        guard current != previous else { return }
        UserDefaults.standard.set(current.rawValue, forKey: key)

        if current > previous {
            // Escalation: green→orange, green→red, orange→red
            notifyEscalation(metric: metric, label: label, pct: pct, level: current, thresholds: thresholds)
        } else if current == .green && previous > .green {
            // Recovery: back to green
            notifyRecovery(metric: metric, label: label, pct: pct)
        }
    }

    private static func notifyEscalation(metric: String, label: String, pct: Int, level: UsageLevel, thresholds: UsageThresholds) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch level {
        case .orange:
            content.title = "⚠️ \(label) — \(pct)%"
            content.body = String(format: String(localized: "notif.orange.body"), thresholds.warningPercent)
        case .red:
            content.title = "🔴 \(label) — \(pct)%"
            content.body = String(localized: "notif.red.body")
        case .green:
            return
        }

        send(id: "escalation_\(metric)", content: content)
    }

    private static func notifyRecovery(metric: String, label: String, pct: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🟢 \(label) — \(pct)%"
        content.body = String(localized: "notif.green.body")
        content.sound = .default

        send(id: "recovery_\(metric)", content: content)
    }

    private static func send(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil // Immediate
        )
        center.add(request)
    }
}

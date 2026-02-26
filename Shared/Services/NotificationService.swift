import Foundation
import UserNotifications

// MARK: - Usage Level

enum UsageLevel: Int, Comparable {
    case green = 0
    case orange = 1
    case red = 2

    static func < (lhs: UsageLevel, rhs: UsageLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func from(pct: Int, thresholds: UsageThresholds = .default) -> UsageLevel {
        if pct >= thresholds.criticalPercent { return .red }
        if pct >= thresholds.warningPercent { return .orange }
        return .green
    }
}

// MARK: - Notification Delegate

/// Allows notifications to display as banners even when the app is in the foreground.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Notification Service

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

    func checkThresholds(
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        pacingZone: PacingZone?,
        thresholds: UsageThresholds
    ) {
        check(metric: "fiveHour", label: String(localized: "metric.session"),
              snapshot: fiveHour, metricType: .session, pacingZone: pacingZone, thresholds: thresholds)
        check(metric: "sevenDay", label: String(localized: "metric.weekly"),
              snapshot: sevenDay, metricType: .weekly, pacingZone: nil, thresholds: thresholds)
        check(metric: "sonnet", label: String(localized: "metric.sonnet"),
              snapshot: sonnet, metricType: .weekly, pacingZone: nil, thresholds: thresholds)
    }

    private func check(
        metric: String,
        label: String,
        snapshot: MetricSnapshot,
        metricType: NotificationBodyFormatter.MetricType,
        pacingZone: PacingZone?,
        thresholds: UsageThresholds
    ) {
        let key = "lastLevel_\(metric)"
        let previousRaw = UserDefaults.standard.integer(forKey: key)
        let previous = UsageLevel(rawValue: previousRaw) ?? .green
        let current = UsageLevel.from(pct: snapshot.pct, thresholds: thresholds)

        guard current != previous else { return }
        UserDefaults.standard.set(current.rawValue, forKey: key)

        if current > previous {
            notifyEscalation(metric: metric, label: label, pct: snapshot.pct, level: current,
                             metricType: metricType, resetsAt: snapshot.resetsAt, pacingZone: pacingZone, thresholds: thresholds)
        } else if current == .green && previous > .green {
            notifyRecovery(metric: metric, label: label, pct: snapshot.pct,
                           metricType: metricType, resetsAt: snapshot.resetsAt)
        }
    }

    private func notifyEscalation(
        metric: String, label: String, pct: Int, level: UsageLevel,
        metricType: NotificationBodyFormatter.MetricType, resetsAt: Date?,
        pacingZone: PacingZone?, thresholds: UsageThresholds
    ) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch level {
        case .orange:
            content.title = "\u{26a0}\u{fe0f} \(label) — \(pct)%"
        case .red:
            content.title = "\u{1f534} \(label) — \(pct)%"
        case .green:
            return
        }

        content.body = NotificationBodyFormatter.escalationBody(
            metricType: metricType,
            level: level,
            resetsAt: resetsAt,
            pacingZone: pacingZone,
            thresholds: thresholds
        )

        send(id: "escalation_\(metric)", content: content)
    }

    private func notifyRecovery(
        metric: String, label: String, pct: Int,
        metricType: NotificationBodyFormatter.MetricType, resetsAt: Date?
    ) {
        let content = UNMutableNotificationContent()
        content.title = "\u{1f7e2} \(label) — \(pct)%"
        content.body = NotificationBodyFormatter.recoveryBody(
            metricType: metricType,
            resetsAt: resetsAt
        )
        content.sound = .default
        send(id: "recovery_\(metric)", content: content)
    }

    private func send(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }
}

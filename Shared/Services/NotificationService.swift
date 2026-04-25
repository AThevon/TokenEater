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

    /// Threshold-only level. Used as fallback and when smart color is disabled.
    static func from(pct: Int, thresholds: UsageThresholds = .default) -> UsageLevel {
        if pct >= thresholds.criticalPercent { return .red }
        if pct >= thresholds.warningPercent { return .orange }
        return .green
    }

    /// Mirrors `ThemeColors.smartGaugeColor` so notifications align with the
    /// gauge color the user actually sees. When smart is OFF or no resetDate
    /// is available, falls back to the threshold computation.
    static func from(
        smartUtilization utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds = .default,
        now: Date = Date()
    ) -> UsageLevel {
        if utilization >= 100 { return .red }
        guard let resetDate, windowDuration > 0 else {
            return from(pct: Int(utilization), thresholds: thresholds)
        }
        let remaining = max(resetDate.timeIntervalSince(now), 0)
        let remainingFraction = max(0, min(1, remaining / windowDuration))
        let risk = utilization * remainingFraction
        if risk > 30 { return .red }
        if risk > 20 { return .orange }
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

// MARK: - Surface

/// Identifier for each metric the service tracks. Drives copy lookup, the
/// last-level UserDefaults key, and the toggle gate.
private enum Surface: String {
    case fiveHour
    case weekly
    case sonnet
    case design

    /// `weekly` and `sonnet`/`design` share the long-form body (date-based)
    /// but each gets its own title to avoid generic alerts.
    var bodyFamily: String {
        self == .fiveHour ? "fivehour" : rawValue
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
        content.title = String(localized: "notif.title.test")
        content.body = String(localized: "notif.body.test")
        content.sound = .default
        send(id: "test_\(Date().timeIntervalSince1970)", content: content)
    }

    // MARK: - Main evaluation

    func evaluate(
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        design: MetricSnapshot,
        sessionPacing: PacingZone?,
        weeklyPacing: PacingZone?,
        extraUsage: ExtraUsage?,
        toggles: NotificationToggles
    ) {
        // Threshold / smart-aware notifications, one surface at a time.
        if toggles.trackFiveHour {
            checkSurface(.fiveHour, snapshot: fiveHour, pacing: sessionPacing, toggles: toggles)
        }
        if toggles.trackWeekly {
            checkSurface(.weekly, snapshot: sevenDay, pacing: weeklyPacing, toggles: toggles)
        }
        if toggles.trackSonnet {
            checkSurface(.sonnet, snapshot: sonnet, pacing: weeklyPacing, toggles: toggles)
        }
        if toggles.trackDesign {
            checkSurface(.design, snapshot: design, pacing: weeklyPacing, toggles: toggles)
        }

        // Pacing zone transitions, gated independently from threshold alerts.
        if let zone = sessionPacing {
            checkPacingTransition(zone, surface: .fiveHour, toggles: toggles)
        }
        if let zone = weeklyPacing {
            checkPacingTransition(zone, surface: .weekly, toggles: toggles)
        }

        // Extra credits pool.
        if toggles.extraCredits, let extra = extraUsage, extra.isEnabled {
            checkExtraCredits(extra, toggles: toggles)
        }
    }

    // MARK: - Surface check

    private func checkSurface(
        _ surface: Surface,
        snapshot: MetricSnapshot,
        pacing: PacingZone?,
        toggles: NotificationToggles
    ) {
        let key = "lastLevel_\(surface.rawValue)"
        let previousRaw = UserDefaults.standard.integer(forKey: key)
        let previous = UsageLevel(rawValue: previousRaw) ?? .green
        let current: UsageLevel = toggles.smartColorEnabled
            ? .from(smartUtilization: snapshot.utilization,
                    resetDate: snapshot.resetsAt,
                    windowDuration: snapshot.windowDuration,
                    thresholds: toggles.thresholds)
            : .from(pct: snapshot.pct, thresholds: toggles.thresholds)

        guard current != previous else { return }
        UserDefaults.standard.set(current.rawValue, forKey: key)

        if current > previous {
            notifyEscalation(surface: surface, level: current, snapshot: snapshot, pacing: pacing)
        } else if current == .green && previous > .green && toggles.sendRecovery {
            notifyRecovery(surface: surface, snapshot: snapshot)
        }
    }

    private func notifyEscalation(
        surface: Surface,
        level: UsageLevel,
        snapshot: MetricSnapshot,
        pacing: PacingZone?
    ) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.title = title(for: surface, level: level, pacing: pacing)
        content.body = body(for: surface, level: level, snapshot: snapshot, pacing: pacing)
        send(id: "escalation_\(surface.rawValue)", content: content)
    }

    private func notifyRecovery(surface: Surface, snapshot: MetricSnapshot) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.title = String(localized: String.LocalizationValue("notif.title.\(surface.bodyFamily).green"))
        content.body = recoveryBody(surface: surface, resetsAt: snapshot.resetsAt)
        send(id: "recovery_\(surface.rawValue)", content: content)
    }

    // MARK: - Pacing transitions

    private func checkPacingTransition(_ zone: PacingZone, surface: Surface, toggles: NotificationToggles) {
        let key = "lastPacing_\(surface.rawValue)"
        let previous = UserDefaults.standard.string(forKey: key) ?? PacingZone.onTrack.rawValue

        // Only fire on entry to a "loud" zone, and only if the toggle for that
        // zone is on. Recovery to chill / onTrack stays silent (the absence of
        // the alert IS the recovery signal).
        if zone.rawValue == previous { return }
        UserDefaults.standard.set(zone.rawValue, forKey: key)

        switch zone {
        case .hot:
            guard toggles.pacingHot else { return }
            firePacing(zone: .hot)
        case .warning:
            guard toggles.pacingWarning else { return }
            firePacing(zone: .warning)
        case .chill, .onTrack:
            return
        }
    }

    private func firePacing(zone: PacingZone) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.title = String(localized: String.LocalizationValue("notif.title.pacing.\(zone.rawValue)"))
        content.body = String(localized: String.LocalizationValue("notif.body.pacing.\(zone.rawValue)"))
        send(id: "pacing_\(zone.rawValue)", content: content)
    }

    // MARK: - Extra credits

    private func checkExtraCredits(_ extra: ExtraUsage, toggles: NotificationToggles) {
        let pct = Int(extra.utilization ?? 0)
        let level = UsageLevel.from(pct: pct, thresholds: toggles.thresholds)
        let key = "lastLevel_extra"
        let previousRaw = UserDefaults.standard.integer(forKey: key)
        let previous = UsageLevel(rawValue: previousRaw) ?? .green
        guard level != previous else { return }
        UserDefaults.standard.set(level.rawValue, forKey: key)

        switch level {
        case .orange, .red:
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.title = String(localized: String.LocalizationValue("notif.title.extra.\(level == .red ? "red" : "orange")"))
            content.body = String(format: String(localized: "notif.body.extra.\(level == .red ? "red" : "orange")"), pct)
            send(id: "escalation_extra", content: content)
        case .green where previous > .green && toggles.sendRecovery:
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.title = String(localized: "notif.title.extra.green")
            content.body = String(localized: "notif.body.extra.green")
            send(id: "recovery_extra", content: content)
        default:
            return
        }
    }

    // MARK: - Token expired

    func notifyTokenExpired(toggle: Bool) {
        guard toggle else { return }
        let key = "lastTokenExpiredFiredAt"
        let now = Date()
        // De-dupe: only one token-expired notif per hour.
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           now.timeIntervalSince(last) < 3600 {
            return
        }
        UserDefaults.standard.set(now, forKey: key)

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.title = String(localized: "notif.title.token")
        content.body = String(localized: "notif.body.token")
        send(id: "token_expired", content: content)
    }

    // MARK: - Reset reminders (scheduled)

    func scheduleResetReminders(
        sessionResetsAt: Date?,
        weeklyResetsAt: Date?,
        toggles: NotificationToggles
    ) {
        // Cancel previous schedules so a moving target doesn't pile up.
        center.removePendingNotificationRequests(withIdentifiers: [
            "reminder_session", "reminder_weekly",
        ])

        if toggles.resetReminderSession, let target = sessionResetsAt?.addingTimeInterval(-15 * 60),
           target.timeIntervalSinceNow > 0 {
            schedule(
                id: "reminder_session",
                titleKey: "notif.title.reminder.session",
                bodyKey: "notif.body.reminder.session",
                fireDate: target
            )
        }
        if toggles.resetReminderWeekly, let target = weeklyResetsAt?.addingTimeInterval(-3600),
           target.timeIntervalSinceNow > 0 {
            schedule(
                id: "reminder_weekly",
                titleKey: "notif.title.reminder.weekly",
                bodyKey: "notif.body.reminder.weekly",
                fireDate: target
            )
        }
    }

    private func schedule(id: String, titleKey: String, bodyKey: String, fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: String.LocalizationValue(titleKey))
        content.body = String(localized: String.LocalizationValue(bodyKey))
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Title / body lookups

    private func title(for surface: Surface, level: UsageLevel, pacing: PacingZone?) -> String {
        // 5h orange has 4 pacing-aware variants. Everything else is one-per-level.
        if surface == .fiveHour, level == .orange, let pacing {
            return String(localized: String.LocalizationValue("notif.title.fivehour.orange.\(pacing.rawValue)"))
        }
        let levelKey = level == .red ? "red" : (level == .orange ? "orange" : "green")
        return String(localized: String.LocalizationValue("notif.title.\(surface.bodyFamily).\(levelKey)"))
    }

    private func body(for surface: Surface, level: UsageLevel, snapshot: MetricSnapshot, pacing: PacingZone?) -> String {
        let resetsAt = snapshot.resetsAt
        switch surface {
        case .fiveHour:
            if let resetsAt, resetsAt.timeIntervalSinceNow > 0 {
                let countdown = NotificationBodyFormatter.formatCountdown(from: Date(), to: resetsAt)
                let pacingKey = (level == .orange) ? (pacing?.rawValue ?? "ontrack") : "red"
                let key = level == .red
                    ? "notif.body.fivehour.red"
                    : "notif.body.fivehour.orange.\(pacingKey)"
                return String(format: String(localized: String.LocalizationValue(key)), countdown)
            }
            return level == .red
                ? String(localized: "notif.body.fivehour.red.fallback")
                : String(localized: "notif.body.fivehour.orange.fallback")
        case .weekly, .sonnet, .design:
            if let resetsAt, resetsAt.timeIntervalSinceNow > 0 {
                let dateTime = NotificationBodyFormatter.formatDateTime(resetsAt)
                let key = level == .red
                    ? "notif.body.\(surface.bodyFamily).red"
                    : "notif.body.\(surface.bodyFamily).orange"
                return String(format: String(localized: String.LocalizationValue(key)), dateTime)
            }
            return level == .red
                ? String(localized: String.LocalizationValue("notif.body.\(surface.bodyFamily).red.fallback"))
                : String(localized: String.LocalizationValue("notif.body.\(surface.bodyFamily).orange.fallback"))
        }
    }

    private func recoveryBody(surface: Surface, resetsAt: Date?) -> String {
        guard let resetsAt, resetsAt.timeIntervalSinceNow > 0 else {
            return String(localized: String.LocalizationValue("notif.body.\(surface.bodyFamily).green.fallback"))
        }
        switch surface {
        case .fiveHour:
            let time = NotificationBodyFormatter.formatTime(resetsAt)
            return String(format: String(localized: "notif.body.fivehour.green"), time)
        case .weekly, .sonnet, .design:
            let dateTime = NotificationBodyFormatter.formatDateTime(resetsAt)
            return String(format: String(localized: String.LocalizationValue("notif.body.\(surface.bodyFamily).green")), dateTime)
        }
    }

    // MARK: - Send

    private func send(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }
}

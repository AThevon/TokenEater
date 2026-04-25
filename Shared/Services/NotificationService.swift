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

    /// Mirrors `ThemeColors.smartLevel` so notifications align with the gauge
    /// color the user actually sees. Couples threshold severity with pacing
    /// severity, applies the reset-imminent override, and falls back to the
    /// pure threshold path when no resetDate / windowDuration is available.
    static func from(
        smartUtilization utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds = .default,
        pacingMargin: Double = 10,
        now: Date = Date()
    ) -> UsageLevel {
        // Reuse the same decision tree as the gauge so the user-visible
        // signals stay in sync. We use the default theme since the threshold
        // logic only depends on `thresholds`, not on the colour palette.
        let level = ThemeColors.default.smartLevel(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now
        )
        switch level {
        case .critical: return .red
        case .warning:  return .orange
        case .normal:   return .green
        }
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
        // Master switch. When the user flipped notifications off in Settings,
        // we skip every per-event check (and also drop any pending scheduled
        // reminders so a switch-back doesn't fire stale ones).
        guard toggles.masterEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [
                "reminder_session", "reminder_weekly",
            ])
            return
        }

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
        content.title = NSLocalizedString("notif.title.\(surface.bodyFamily).green", comment: "")
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
        content.title = NSLocalizedString("notif.title.pacing.\(zone.rawValue)", comment: "")
        content.body = NSLocalizedString("notif.body.pacing.\(zone.rawValue)", comment: "")
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
            let extraKey = level == .red ? "red" : "orange"
            content.title = NSLocalizedString("notif.title.extra.\(extraKey)", comment: "")
            content.body = String(format: NSLocalizedString("notif.body.extra.\(extraKey)", comment: ""), pct)
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
        content.title = NSLocalizedString(titleKey, comment: "")
        content.body = NSLocalizedString(bodyKey, comment: "")
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Title / body lookups

    private func title(for surface: Surface, level: UsageLevel, pacing: PacingZone?) -> String {
        // Runtime-composed keys must go through `NSLocalizedString` to actually
        // hit the .strings file. `String(localized: String.LocalizationValue(_))`
        // takes a runtime String as a default value rather than as a key, so it
        // happily returns the literal "notif.title.fivehour.green" if used here.
        // PacingZone.onTrack has rawValue "onTrack" (camelCase) but the strings
        // use lowercase to keep keys stylistically aligned, so we normalise.
        if surface == .fiveHour, level == .orange, let pacing {
            return NSLocalizedString("notif.title.fivehour.orange.\(pacing.rawValue.lowercased())", comment: "")
        }
        let levelKey = level == .red ? "red" : (level == .orange ? "orange" : "green")
        return NSLocalizedString("notif.title.\(surface.bodyFamily).\(levelKey)", comment: "")
    }

    private func body(for surface: Surface, level: UsageLevel, snapshot: MetricSnapshot, pacing: PacingZone?) -> String {
        let resetsAt = snapshot.resetsAt
        switch surface {
        case .fiveHour:
            if let resetsAt, resetsAt.timeIntervalSinceNow > 0 {
                let countdown = NotificationBodyFormatter.formatCountdown(from: Date(), to: resetsAt)
                let pacingKey = (level == .orange) ? (pacing?.rawValue.lowercased() ?? "ontrack") : "red"
                let key = level == .red
                    ? "notif.body.fivehour.red"
                    : "notif.body.fivehour.orange.\(pacingKey)"
                return String(format: NSLocalizedString(key, comment: ""), countdown)
            }
            return level == .red
                ? NSLocalizedString("notif.body.fivehour.red.fallback", comment: "")
                : NSLocalizedString("notif.body.fivehour.orange.fallback", comment: "")
        case .weekly, .sonnet, .design:
            if let resetsAt, resetsAt.timeIntervalSinceNow > 0 {
                let dateTime = NotificationBodyFormatter.formatDateTime(resetsAt)
                let key = level == .red
                    ? "notif.body.\(surface.bodyFamily).red"
                    : "notif.body.\(surface.bodyFamily).orange"
                return String(format: NSLocalizedString(key, comment: ""), dateTime)
            }
            return level == .red
                ? NSLocalizedString("notif.body.\(surface.bodyFamily).red.fallback", comment: "")
                : NSLocalizedString("notif.body.\(surface.bodyFamily).orange.fallback", comment: "")
        }
    }

    private func recoveryBody(surface: Surface, resetsAt: Date?) -> String {
        guard let resetsAt, resetsAt.timeIntervalSinceNow > 0 else {
            return NSLocalizedString("notif.body.\(surface.bodyFamily).green.fallback", comment: "")
        }
        switch surface {
        case .fiveHour:
            let time = NotificationBodyFormatter.formatTime(resetsAt)
            return String(format: NSLocalizedString("notif.body.fivehour.green", comment: ""), time)
        case .weekly, .sonnet, .design:
            let dateTime = NotificationBodyFormatter.formatDateTime(resetsAt)
            return String(format: NSLocalizedString("notif.body.\(surface.bodyFamily).green", comment: ""), dateTime)
        }
    }

    // MARK: - Send

    private func send(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }
}

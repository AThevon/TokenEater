import Foundation

enum NotificationBodyFormatter {

    enum MetricType {
        case session
        case weekly
    }

    // MARK: - Escalation (orange / red)

    static func escalationBody(
        metricType: MetricType,
        level: UsageLevel,
        resetsAt: Date?,
        pacingZone: PacingZone?,
        thresholds: UsageThresholds,
        now: Date = Date()
    ) -> String {
        guard let resetsAt, resetsAt.timeIntervalSince(now) > 0 else {
            return fallbackEscalation(level: level, thresholds: thresholds)
        }

        switch (level, metricType) {
        case (.orange, .session):
            let countdown = formatCountdown(from: now, to: resetsAt)
            let time = formatTime(resetsAt)
            let key: String
            switch pacingZone ?? .onTrack {
            case .chill: key = "notif.orange.body.session.chill"
            case .onTrack: key = "notif.orange.body.session.ontrack"
            case .hot: key = "notif.orange.body.session.hot"
            }
            return String(format: String(localized: String.LocalizationValue(key)), countdown, time)

        case (.orange, .weekly):
            let dateTime = formatDateTime(resetsAt)
            return String(format: String(localized: "notif.orange.body.weekly"), dateTime)

        case (.red, .session):
            let countdown = formatCountdown(from: now, to: resetsAt)
            let time = formatTime(resetsAt)
            return String(format: String(localized: "notif.red.body.session"), countdown, time)

        case (.red, .weekly):
            let dateTime = formatDateTime(resetsAt)
            return String(format: String(localized: "notif.red.body.weekly"), dateTime)

        case (.green, _):
            return fallbackEscalation(level: level, thresholds: thresholds)
        }
    }

    // MARK: - Recovery (green)

    static func recoveryBody(
        metricType: MetricType,
        resetsAt: Date?,
        now: Date = Date()
    ) -> String {
        guard let resetsAt, resetsAt.timeIntervalSince(now) > 0 else {
            return String(localized: "notif.green.body")
        }

        switch metricType {
        case .session:
            let time = formatTime(resetsAt)
            return String(format: String(localized: "notif.green.body.session"), time)
        case .weekly:
            let dateTime = formatDateTime(resetsAt)
            return String(format: String(localized: "notif.green.body.weekly"), dateTime)
        }
    }

    // MARK: - Time Formatting

    static func formatCountdown(from now: Date, to target: Date) -> String {
        let diff = target.timeIntervalSince(now)
        guard diff > 0 else { return String(localized: "relative.now") }

        let totalMinutes = Int(diff) / 60
        let h = totalMinutes / 60
        let m = totalMinutes % 60

        if h >= 24 {
            let d = h / 24
            let remainH = h % 24
            return String(format: String(localized: "duration.days.hours"), d, remainH)
        } else if h > 0 {
            return "\(h)h \(m)min"
        } else {
            return "\(m)min"
        }
    }

    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "EEE MMM d, h:mm a",
            options: 0,
            locale: .current
        )
        return formatter.string(from: date)
    }

    // MARK: - Fallback

    private static func fallbackEscalation(level: UsageLevel, thresholds: UsageThresholds) -> String {
        switch level {
        case .orange:
            return String(format: String(localized: "notif.orange.body"), thresholds.warningPercent)
        case .red:
            return String(localized: "notif.red.body")
        case .green:
            return ""
        }
    }
}

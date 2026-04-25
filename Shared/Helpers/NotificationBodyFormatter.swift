import Foundation

/// Time formatting helpers used by `NotificationService` to build notification
/// bodies. Pre-v5.0 this enum also owned the body-string assembly logic, but
/// the service now constructs strings directly so this stays focused on date
/// rendering.
enum NotificationBodyFormatter {

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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "EEE MMM d, h:mm a",
            options: 0,
            locale: .current
        )
        return f
    }()

    static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func formatDateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }
}

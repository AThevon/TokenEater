import Foundation
import UserNotifications

struct MetricSnapshot {
    let pct: Int
    /// Floating-point utilization as returned by the API (0..100). Kept alongside
    /// `pct` so the smart-color formula can avoid double-rounding.
    let utilization: Double
    let resetsAt: Date?
    /// Total length of the rolling window (5h for session, 7d for weekly buckets).
    /// Required for the smart risk computation: smaller window -> different timing.
    let windowDuration: TimeInterval

    init(pct: Int, resetsAt: Date?, windowDuration: TimeInterval = 0, utilization: Double? = nil) {
        self.pct = pct
        self.resetsAt = resetsAt
        self.windowDuration = windowDuration
        self.utilization = utilization ?? Double(pct)
    }
}

/// Bundle of every per-event toggle and the global behaviour flags the service
/// needs to decide whether (and how) to fire a notification. Built from
/// `SettingsStore` and re-built on every refresh so toggle changes are
/// reflected without restarting.
struct NotificationToggles {
    /// Master gate. When false, every per-event toggle is ignored and no
    /// notification fires. Lets the user silence everything without losing
    /// their per-event configuration.
    let masterEnabled: Bool
    let trackFiveHour: Bool
    let trackWeekly: Bool
    let trackSonnet: Bool
    let trackDesign: Bool
    let sendRecovery: Bool
    let pacingHot: Bool
    let pacingWarning: Bool
    let resetReminderSession: Bool
    let resetReminderWeekly: Bool
    let extraCredits: Bool
    let tokenExpired: Bool
    let smartColorEnabled: Bool
    let thresholds: UsageThresholds
}

protocol NotificationServiceProtocol {
    func setupDelegate()
    func requestPermission()
    func checkAuthorizationStatus() async -> UNAuthorizationStatus
    func sendTest()
    func evaluate(
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        design: MetricSnapshot,
        sessionPacing: PacingZone?,
        weeklyPacing: PacingZone?,
        extraUsage: ExtraUsage?,
        toggles: NotificationToggles
    )
    func notifyTokenExpired(toggle: Bool)
    func scheduleResetReminders(
        sessionResetsAt: Date?,
        weeklyResetsAt: Date?,
        toggles: NotificationToggles
    )
}

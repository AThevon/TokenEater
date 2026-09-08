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

/// Codex-specific notification switches. Grouped in their own struct (with a
/// default) so adding one never breaks the memberwise initialiser every call
/// site of `NotificationToggles` uses.
struct CodexNotificationToggles: Equatable {
    /// Codex sub-master. The global `masterEnabled` still wins over it.
    var enabled: Bool = true
    var trackSession: Bool = true
    var trackWeekly: Bool = true
    /// The "your quota is back" alert, fired when a window actually rolls over
    /// rather than when usage merely eases off.
    var windowReset: Bool = true
    var resetReminderSession: Bool = false
    var resetReminderWeekly: Bool = false
    var tokenExpired: Bool = true

    static let `default` = CodexNotificationToggles()
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
    let trackFable: Bool
    let sendRecovery: Bool
    let pacingHot: Bool
    let pacingWarning: Bool
    let resetReminderSession: Bool
    let resetReminderWeekly: Bool
    /// Minutes before the 5h reset that the session reminder should fire.
    let resetReminderSessionOffsetMinutes: Int
    /// Minutes before the weekly reset that the weekly reminder should fire.
    let resetReminderWeeklyOffsetMinutes: Int
    let extraCredits: Bool
    let tokenExpired: Bool
    let smartColorEnabled: Bool
    let smartColorProfile: SmartColorProfile
    let pacingMargin: Double
    let thresholds: UsageThresholds
    /// Fire a notification when a monitored vendor goes degraded/down.
    let vendorDegraded: Bool
    /// Fire a notification when a monitored vendor recovers to healthy.
    let vendorRestored: Bool
    /// Codex switches. A `var` with a default so existing call sites keep
    /// compiling unchanged.
    var codex: CodexNotificationToggles = .default
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
        fable: MetricSnapshot,
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
    func checkVendorHealth(_ status: VendorStatus, toggles: NotificationToggles)
    /// One call per successful Codex refresh: threshold escalations, pacing
    /// transitions, the window-reset alert and the reset reminders.
    func evaluateCodex(windows: [CodexWindowSnapshot], toggles: NotificationToggles)
    func notifyCodexTokenExpired(toggles: NotificationToggles)
    /// Drops any pending Codex reminder, for when the provider is switched off.
    func cancelCodexReminders()
}

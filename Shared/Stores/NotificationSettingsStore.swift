import Foundation

/// Notification-domain slice of the user settings. Extracted from SettingsStore
/// as part of the fat-store split, same pattern as `PacingSettingsStore`. Owns
/// the master switch + every per-event toggle and its own UserDefaults
/// persistence. No shared-file mirror: the widget doesn't render notifications.
///
/// `enabled` is the master switch: when off, `NotificationService.evaluate`
/// bails out before touching the per-event toggles, so the user keeps their
/// granular config while silencing the whole pipeline.
@MainActor
final class NotificationSettingsStore: ObservableObject {
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "notificationsEnabled") }
    }
    @Published var trackFiveHour: Bool {
        didSet { UserDefaults.standard.set(trackFiveHour, forKey: "notifTrackFiveHour") }
    }
    @Published var trackWeekly: Bool {
        didSet { UserDefaults.standard.set(trackWeekly, forKey: "notifTrackWeekly") }
    }
    @Published var trackSonnet: Bool {
        didSet { UserDefaults.standard.set(trackSonnet, forKey: "notifTrackSonnet") }
    }
    @Published var trackDesign: Bool {
        didSet { UserDefaults.standard.set(trackDesign, forKey: "notifTrackDesign") }
    }
    /// When false, only escalations (orange / red) fire. Recovery to green stays silent.
    @Published var sendRecovery: Bool {
        didSet { UserDefaults.standard.set(sendRecovery, forKey: "notifSendRecovery") }
    }
    /// Pacing zone transitions
    @Published var pacingHot: Bool {
        didSet { UserDefaults.standard.set(pacingHot, forKey: "notifPacingHot") }
    }
    @Published var pacingWarning: Bool {
        didSet { UserDefaults.standard.set(pacingWarning, forKey: "notifPacingWarning") }
    }
    /// Scheduled reminders (user-configurable offset before reset).
    @Published var resetReminderSession: Bool {
        didSet { UserDefaults.standard.set(resetReminderSession, forKey: "notifResetReminderSession") }
    }
    @Published var resetReminderWeekly: Bool {
        didSet { UserDefaults.standard.set(resetReminderWeekly, forKey: "notifResetReminderWeekly") }
    }
    /// Minutes before the 5h session resets at which to fire the reminder.
    /// Defaults to 15. Allowed values are validated by the picker, not enforced here.
    @Published var resetReminderSessionOffset: Int {
        didSet { UserDefaults.standard.set(resetReminderSessionOffset, forKey: "notifResetReminderSessionOffset") }
    }
    /// Minutes before the weekly bucket resets at which to fire the reminder.
    /// Defaults to 60.
    @Published var resetReminderWeeklyOffset: Int {
        didSet { UserDefaults.standard.set(resetReminderWeeklyOffset, forKey: "notifResetReminderWeeklyOffset") }
    }
    /// Paid extra credits pool transitions
    @Published var extraCredits: Bool {
        didSet { UserDefaults.standard.set(extraCredits, forKey: "notifExtraCredits") }
    }
    /// Token expired / authentication issues
    @Published var tokenExpired: Bool {
        didSet { UserDefaults.standard.set(tokenExpired, forKey: "notifTokenExpired") }
    }
    /// Vendor outage: notify when a monitored vendor goes degraded/down.
    @Published var vendorDegraded: Bool {
        didSet { UserDefaults.standard.set(vendorDegraded, forKey: "notifVendorDegraded") }
    }
    /// Vendor outage: notify when a monitored vendor recovers.
    @Published var vendorRestored: Bool {
        didSet { UserDefaults.standard.set(vendorRestored, forKey: "notifVendorRestored") }
    }

    init() {
        // Defaults below apply only on first launch (no value yet in
        // UserDefaults) - per `SettingsDefaults.bool/int` semantics.
        self.enabled = SettingsDefaults.bool(key: "notificationsEnabled", default: true)
        self.trackFiveHour = SettingsDefaults.bool(key: "notifTrackFiveHour", default: true)
        self.trackWeekly = SettingsDefaults.bool(key: "notifTrackWeekly", default: true)
        self.trackSonnet = SettingsDefaults.bool(key: "notifTrackSonnet", default: false)
        self.trackDesign = SettingsDefaults.bool(key: "notifTrackDesign", default: true)
        self.sendRecovery = SettingsDefaults.bool(key: "notifSendRecovery", default: true)
        self.pacingHot = SettingsDefaults.bool(key: "notifPacingHot", default: true)
        self.pacingWarning = SettingsDefaults.bool(key: "notifPacingWarning", default: false)
        self.resetReminderSession = SettingsDefaults.bool(key: "notifResetReminderSession", default: false)
        self.resetReminderWeekly = SettingsDefaults.bool(key: "notifResetReminderWeekly", default: false)
        self.resetReminderSessionOffset = SettingsDefaults.int(key: "notifResetReminderSessionOffset", default: 15)
        self.resetReminderWeeklyOffset = SettingsDefaults.int(key: "notifResetReminderWeeklyOffset", default: 60)
        self.extraCredits = SettingsDefaults.bool(key: "notifExtraCredits", default: true)
        self.tokenExpired = SettingsDefaults.bool(key: "notifTokenExpired", default: false)
        self.vendorDegraded = SettingsDefaults.bool(key: "notifVendorDegraded", default: true)
        self.vendorRestored = SettingsDefaults.bool(key: "notifVendorRestored", default: true)
    }
}

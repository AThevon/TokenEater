import Foundation

/// Transition state for the notification escalation/recovery state machine.
/// Isolated behind a protocol so the level/pacing/token-expired logic is
/// testable without touching real UserDefaults.
protocol NotificationStateStore: AnyObject {
    /// True once a baseline has been written for `key`. `lastLevel` cannot
    /// answer this on its own: an absent key and a stored `.green` both read
    /// as 0, so the escalation machine would treat a first observation as a
    /// transition out of green and fire on it.
    func hasBaseline(forKey key: String) -> Bool
    func lastLevel(forKey key: String) -> Int
    func setLastLevel(_ value: Int, forKey key: String)
    func lastPacing(forKey key: String) -> String?
    func setLastPacing(_ value: String, forKey key: String)
    /// Last-seen reset boundary per surface. Lets the recovery ("new cycle")
    /// alert fire only on a real window reset, not a mid-window Smart Color
    /// level dip (#244).
    func lastResetsAt(forKey key: String) -> Date?
    func setLastResetsAt(_ date: Date, forKey key: String)
    /// True once the generic Claude token alert went out for the current
    /// run of failures. Cleared by the next successful refresh, so a failure
    /// that persists for days alerts once, not every hour.
    func tokenAlertSent() -> Bool
    func setTokenAlertSent(_ sent: Bool)
    /// Expiry date of the login the expired-login alert last announced. A
    /// renewed login expires later, which opens the next episode. Kept apart
    /// from `tokenAlertSent` so neither alert can swallow the other.
    func loginExpiredAlertedFor() -> Date?
    func setLoginExpiredAlertedFor(_ expiresAt: Date)
    /// Last observed utilization per surface. Paired with `lastResetsAt` it
    /// tells a real window rollover apart from the sliding deadline an unused
    /// window reports on every poll (see `CodexResetDetector`).
    func lastUtilization(forKey key: String) -> Double?
    func setLastUtilization(_ value: Double, forKey key: String)
    func codexTokenExpiredFiredAt() -> Date?
    func setCodexTokenExpiredFiredAt(_ date: Date)
}

final class UserDefaultsNotificationStateStore: NotificationStateStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func hasBaseline(forKey key: String) -> Bool { defaults.object(forKey: key) != nil }
    func lastLevel(forKey key: String) -> Int { defaults.integer(forKey: key) }
    func setLastLevel(_ value: Int, forKey key: String) { defaults.set(value, forKey: key) }
    func lastPacing(forKey key: String) -> String? { defaults.string(forKey: key) }
    func setLastPacing(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
    func lastResetsAt(forKey key: String) -> Date? { defaults.object(forKey: key) as? Date }
    func setLastResetsAt(_ date: Date, forKey key: String) { defaults.set(date, forKey: key) }
    func tokenAlertSent() -> Bool { defaults.bool(forKey: "claudeTokenAlertSent") }
    func setTokenAlertSent(_ sent: Bool) { defaults.set(sent, forKey: "claudeTokenAlertSent") }
    func loginExpiredAlertedFor() -> Date? { defaults.object(forKey: "lastLoginExpiredEpisode") as? Date }
    func setLoginExpiredAlertedFor(_ expiresAt: Date) { defaults.set(expiresAt, forKey: "lastLoginExpiredEpisode") }
    func lastUtilization(forKey key: String) -> Double? { defaults.object(forKey: key) as? Double }
    func setLastUtilization(_ value: Double, forKey key: String) { defaults.set(value, forKey: key) }
    func codexTokenExpiredFiredAt() -> Date? { defaults.object(forKey: "lastCodexTokenExpiredFiredAt") as? Date }
    func setCodexTokenExpiredFiredAt(_ date: Date) { defaults.set(date, forKey: "lastCodexTokenExpiredFiredAt") }
}

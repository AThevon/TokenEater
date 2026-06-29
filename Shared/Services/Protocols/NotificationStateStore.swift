import Foundation

/// Transition state for the notification escalation/recovery state machine.
/// Isolated behind a protocol so the level/pacing/token-expired logic is
/// testable without touching real UserDefaults.
protocol NotificationStateStore: AnyObject {
    func lastLevel(forKey key: String) -> Int
    func setLastLevel(_ value: Int, forKey key: String)
    func lastPacing(forKey key: String) -> String?
    func setLastPacing(_ value: String, forKey key: String)
    func tokenExpiredFiredAt() -> Date?
    func setTokenExpiredFiredAt(_ date: Date)
}

final class UserDefaultsNotificationStateStore: NotificationStateStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func lastLevel(forKey key: String) -> Int { defaults.integer(forKey: key) }
    func setLastLevel(_ value: Int, forKey key: String) { defaults.set(value, forKey: key) }
    func lastPacing(forKey key: String) -> String? { defaults.string(forKey: key) }
    func setLastPacing(_ value: String, forKey key: String) { defaults.set(value, forKey: key) }
    func tokenExpiredFiredAt() -> Date? { defaults.object(forKey: "lastTokenExpiredFiredAt") as? Date }
    func setTokenExpiredFiredAt(_ date: Date) { defaults.set(date, forKey: "lastTokenExpiredFiredAt") }
}

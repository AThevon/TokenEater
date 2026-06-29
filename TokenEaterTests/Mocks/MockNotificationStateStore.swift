import Foundation

final class MockNotificationStateStore: NotificationStateStore {
    var levels: [String: Int] = [:]
    var pacings: [String: String] = [:]
    var tokenExpiredAt: Date?

    func lastLevel(forKey key: String) -> Int { levels[key] ?? 0 }
    func setLastLevel(_ value: Int, forKey key: String) { levels[key] = value }
    func lastPacing(forKey key: String) -> String? { pacings[key] }
    func setLastPacing(_ value: String, forKey key: String) { pacings[key] = value }
    func tokenExpiredFiredAt() -> Date? { tokenExpiredAt }
    func setTokenExpiredFiredAt(_ date: Date) { tokenExpiredAt = date }
}

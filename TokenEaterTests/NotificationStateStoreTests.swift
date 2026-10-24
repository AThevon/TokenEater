import Testing
import Foundation

/// Each Claude account keeps its own notification state, so a successful
/// refresh on one account can never re-arm or clear another's alerts.
@Suite("Notification state per account")
struct NotificationStateStoreTests {

    private func freshDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("the main account's keys are the historical ones")
    func mainKeysUnchanged() throws {
        let defaults = try freshDefaults("NotificationStateStoreTests.main")
        defer { defaults.removePersistentDomain(forName: "NotificationStateStoreTests.main") }
        let store = UserDefaultsNotificationStateStore(defaults: defaults)
        store.setLastLevel(2, forKey: "lastLevel_fiveHour")
        store.setTokenAlertSent(true)
        store.setLoginExpiredAlertedFor(Date(timeIntervalSince1970: 10))
        #expect(defaults.integer(forKey: "lastLevel_fiveHour") == 2)
        #expect(defaults.bool(forKey: "claudeTokenAlertSent"))
        #expect(defaults.object(forKey: "lastLoginExpiredEpisode") as? Date == Date(timeIntervalSince1970: 10))
    }

    @Test("an added account suffixes every key, the fixed ones included, and shares nothing")
    func accountKeysSuffixed() throws {
        let defaults = try freshDefaults("NotificationStateStoreTests.account")
        defer { defaults.removePersistentDomain(forName: "NotificationStateStoreTests.account") }
        let main = UserDefaultsNotificationStateStore(defaults: defaults)
        let work = UserDefaultsNotificationStateStore(defaults: defaults, keySuffix: ".acct-w")

        work.setLastLevel(3, forKey: "lastLevel_fiveHour")
        work.setTokenAlertSent(true)
        work.setLastResetsAt(Date(timeIntervalSince1970: 20), forKey: "lastResetsAt_weekly")

        #expect(defaults.integer(forKey: "lastLevel_fiveHour.acct-w") == 3)
        #expect(defaults.bool(forKey: "claudeTokenAlertSent.acct-w"))
        #expect(defaults.object(forKey: "lastResetsAt_weekly.acct-w") as? Date == Date(timeIntervalSince1970: 20))
        #expect(!main.hasBaseline(forKey: "lastLevel_fiveHour"))
        #expect(!main.tokenAlertSent())
        #expect(work.hasBaseline(forKey: "lastLevel_fiveHour"))
    }
}

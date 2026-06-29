import Testing
import Foundation
import Combine

@Suite("NotificationSettingsStore", .serialized)
@MainActor
struct NotificationSettingsStoreTests {

    private let keys = [
        "notificationsEnabled", "notifTrackFiveHour", "notifTrackWeekly",
        "notifTrackSonnet", "notifTrackDesign", "notifSendRecovery",
        "notifPacingHot", "notifPacingWarning",
        "notifResetReminderSession", "notifResetReminderWeekly",
        "notifResetReminderSessionOffset", "notifResetReminderWeeklyOffset",
        "notifExtraCredits", "notifTokenExpired",
    ]
    private func clean() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    @Test("defaults match the first-launch configuration")
    func defaults() {
        clean(); defer { clean() }
        let store = NotificationSettingsStore()
        #expect(store.enabled == true)
        #expect(store.trackFiveHour == true)
        #expect(store.trackWeekly == true)
        #expect(store.trackSonnet == false)
        #expect(store.trackDesign == true)
        #expect(store.sendRecovery == true)
        #expect(store.pacingHot == true)
        #expect(store.pacingWarning == false)
        #expect(store.resetReminderSession == false)
        #expect(store.resetReminderWeekly == false)
        #expect(store.resetReminderSessionOffset == 15)
        #expect(store.resetReminderWeeklyOffset == 60)
        #expect(store.extraCredits == true)
        #expect(store.tokenExpired == false)
    }

    @Test("changing a toggle persists to UserDefaults")
    func togglePersists() {
        clean(); defer { clean() }
        let store = NotificationSettingsStore()
        store.trackSonnet = true
        #expect(UserDefaults.standard.object(forKey: "notifTrackSonnet") as? Bool == true)
        store.resetReminderSessionOffset = 30
        #expect(UserDefaults.standard.object(forKey: "notifResetReminderSessionOffset") as? Int == 30)
    }

    @Test("stored values are read back on load")
    func loadsStoredValues() {
        clean(); defer { clean() }
        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        UserDefaults.standard.set(true, forKey: "notifPacingWarning")
        UserDefaults.standard.set(120, forKey: "notifResetReminderWeeklyOffset")
        let store = NotificationSettingsStore()
        #expect(store.enabled == false)
        #expect(store.pacingWarning == true)
        #expect(store.resetReminderWeeklyOffset == 120)
    }

    @Test("child change relays objectWillChange to SettingsStore parent")
    func relaysToParent() {
        clean(); defer { clean() }
        let parent = SettingsStore(
            notificationService: MockNotificationService(),
            tokenProvider: MockTokenProvider(),
            sharedFileService: MockSharedFileService()
        )
        var fired = false
        let c = parent.objectWillChange.sink { fired = true }
        parent.notification.tokenExpired = true
        #expect(fired == true)
        _ = c
    }

    @Test("SettingsStore forwards read and write through the child")
    func parentForwards() {
        clean(); defer { clean() }
        let parent = SettingsStore(
            notificationService: MockNotificationService(),
            tokenProvider: MockTokenProvider(),
            sharedFileService: MockSharedFileService()
        )
        parent.notifPacingWarning = true
        #expect(parent.notification.pacingWarning == true)
        parent.notifExtraCredits = false
        #expect(parent.notification.extraCredits == false)
    }
}

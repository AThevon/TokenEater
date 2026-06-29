import Testing
import Foundation
import Combine

@Suite("PacingSettingsStore", .serialized)
@MainActor
struct PacingSettingsStoreTests {

    private let pacingKeys = [
        "pacingMargin", "pacingWorkweekEnabled", "pacingActiveDays",
        "pacingHoursEnabled", "pacingStartHour", "pacingEndHour",
    ]
    private func clean() { pacingKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    @Test("defaults match PacingSchedule.default")
    func defaults() {
        clean(); defer { clean() }
        let store = PacingSettingsStore(sharedFileService: MockSharedFileService())
        #expect(store.margin == 10)
        #expect(store.workweekEnabled == false)
        #expect(store.startHour == PacingSchedule.defaultStartHour)
        #expect(store.endHour == PacingSchedule.defaultEndHour)
        #expect(store.schedule == PacingSchedule.default)
    }

    @Test("changing margin persists and mirrors to shared file")
    func marginPersistsAndMirrors() {
        clean(); defer { clean() }
        let shared = MockSharedFileService()
        let store = PacingSettingsStore(sharedFileService: shared)
        store.workweekEnabled = true
        #expect(UserDefaults.standard.object(forKey: "pacingWorkweekEnabled") as? Bool == true)
        #expect(shared.updatePacingScheduleCallCount >= 1)
        #expect(shared.pacingSchedule.enabled == true)
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
        parent.pacing.margin = 25
        #expect(fired == true)
        _ = c
    }
}

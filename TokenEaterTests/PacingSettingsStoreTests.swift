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

    @Test("changing workweekEnabled persists and mirrors to shared file")
    func workweekEnabledPersistsAndMirrors() {
        clean(); defer { clean() }
        let shared = MockSharedFileService()
        let store = PacingSettingsStore(sharedFileService: shared)
        store.workweekEnabled = true
        #expect(UserDefaults.standard.object(forKey: "pacingWorkweekEnabled") as? Bool == true)
        #expect(shared.updatePacingScheduleCallCount >= 1)
        #expect(shared.pacingSchedule.enabled == true)
    }

    @Test("margin snaps to nearest 5 and clamps to 5...30 on load")
    func marginSnapsAndClampsOnLoad() {
        clean(); defer { clean() }
        func loadedMargin(raw: Int) -> Int {
            UserDefaults.standard.set(raw, forKey: "pacingMargin")
            return PacingSettingsStore(sharedFileService: MockSharedFileService()).margin
        }
        #expect(loadedMargin(raw: 13) == 15) // 2.6 -> 3 -> 15
        #expect(loadedMargin(raw: 7) == 5)   // 1.4 -> 1 -> 5
        #expect(loadedMargin(raw: 2) == 5)   // 0.4 -> 0, clamped up to 5
        #expect(loadedMargin(raw: 33) == 30) // 6.6 -> 7 -> 35, clamped to 30
        #expect(loadedMargin(raw: 25) == 25) // exact multiple, unchanged
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

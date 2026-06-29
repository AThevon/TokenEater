import Testing
import Foundation
import Combine

@Suite("OverlaySettingsStore", .serialized)
@MainActor
struct OverlaySettingsStoreTests {

    private let overlayKeys = [
        "overlayEnabled", "overlayDockEffect", "overlayScale", "overlayLeftSide",
        "overlayTriggerZone", "watchersDetailedMode", "watcherStyle",
        "watcherDisplayMode", "watcherScanInterval", "watcherVisibility",
        "watcherAnimationsEnabled",
    ]
    private func clean() { overlayKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    @Test("defaults match the historic SettingsStore values")
    func defaults() {
        clean(); defer { clean() }
        let store = OverlaySettingsStore()
        #expect(store.overlayEnabled == true)
        #expect(store.overlayDockEffect == true)
        #expect(store.overlayScale == 1.1)
        #expect(store.overlayLeftSide == false)
        #expect(store.overlayTriggerZone == .medium)
        #expect(store.watchersDetailedMode == true)
        #expect(store.watcherStyle == .frost)
        #expect(store.watcherDisplayMode == .branchPriority)
        #expect(store.watcherScanInterval == .twoSeconds)
        #expect(store.watcherVisibility == .thirtyMinutes)
        #expect(store.watcherAnimationsEnabled == true)
    }

    @Test("changing overlayEnabled persists to UserDefaults")
    func overlayEnabledPersists() {
        clean(); defer { clean() }
        let store = OverlaySettingsStore()
        store.overlayEnabled = false
        #expect(UserDefaults.standard.object(forKey: "overlayEnabled") as? Bool == false)
    }

    @Test("watcherStyle reads back on a fresh instance and falls back on garbage")
    func watcherStyleRoundTripAndFallback() {
        clean(); defer { clean() }
        let store = OverlaySettingsStore()
        store.watcherStyle = .neon
        #expect(UserDefaults.standard.string(forKey: "watcherStyle") == "neon")
        #expect(OverlaySettingsStore().watcherStyle == .neon)

        UserDefaults.standard.set("cyberpunk", forKey: "watcherStyle")
        #expect(OverlaySettingsStore().watcherStyle == .frost)
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
        parent.overlay.overlayEnabled.toggle()
        #expect(fired == true)
        _ = c
    }
}

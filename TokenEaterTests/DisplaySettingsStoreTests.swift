import Testing
import Foundation
import Combine

@Suite("DisplaySettingsStore", .serialized)
@MainActor
struct DisplaySettingsStoreTests {

    private let displayKeys = [
        "showMenuBar", "launchInBackground", "pinnedMetrics", "resetDisplayFormat",
        "smartColorEnabled", "smartResetColor", "smartColorProfile", "glowIntensity",
        "menuBarStyle", "pacingShape", "sessionPacingDisplayMode", "weeklyPacingDisplayMode",
        "pacingDisplayMode", "resetTextColorHex", "sessionPeriodColorHex",
        "displaySonnet", "displayDesign", "showSessionReset",
    ]
    private func clean() { displayKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    @Test("defaults on a fresh install")
    func defaults() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore(sharedFileService: MockSharedFileService())
        #expect(store.showMenuBar == true)
        #expect(store.launchInBackground == false)
        #expect(store.pinnedMetrics == [.fiveHour, .sevenDay])
        #expect(store.resetDisplayFormat == .relative)
        #expect(store.smartColorEnabled == true)
        #expect(store.smartColorProfile == .default)
        #expect(store.glowIntensity == .glow)
        #expect(store.menuBarStyle == .classic)
        #expect(store.pacingShape == .circle)
        #expect(store.sessionPacingDisplayMode == .dotDelta)
        #expect(store.weeklyPacingDisplayMode == .dotDelta)
        #expect(store.resetTextColorHex == "")
        #expect(store.sessionPeriodColorHex == "")
        #expect(store.displaySonnet == false)
        #expect(store.displayDesign == false)
    }

    @Test("changing menuBarStyle persists to UserDefaults")
    func menuBarStylePersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore(sharedFileService: MockSharedFileService())
        store.menuBarStyle = .badge
        #expect(UserDefaults.standard.string(forKey: "menuBarStyle") == MenuBarStyle.badge.rawValue)
    }

    @Test("changing pinnedMetrics persists the raw value array")
    func pinnedMetricsPersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore(sharedFileService: MockSharedFileService())
        store.pinnedMetrics = [.fiveHour, .sevenDay, .sessionPacing]
        let saved = Set(UserDefaults.standard.stringArray(forKey: "pinnedMetrics") ?? [])
        #expect(saved == ["fiveHour", "sevenDay", "sessionPacing"])
    }

    @Test("smartColorEnabled persists and mirrors to the shared file")
    func smartColorEnabledMirrors() {
        clean(); defer { clean() }
        let shared = MockSharedFileService()
        let store = DisplaySettingsStore(sharedFileService: shared)
        store.smartColorEnabled = false
        #expect(UserDefaults.standard.object(forKey: "smartColorEnabled") as? Bool == false)
        #expect(shared.smartColorEnabled == false)
        #expect(shared.updateSmartColorCallCount >= 1)
    }

    @Test("smartColorProfile persists and mirrors to the shared file")
    func smartColorProfileMirrors() {
        clean(); defer { clean() }
        let shared = MockSharedFileService()
        let store = DisplaySettingsStore(sharedFileService: shared)
        store.smartColorProfile = .vigilant
        #expect(UserDefaults.standard.string(forKey: "smartColorProfile") == SmartColorProfile.vigilant.rawValue)
        #expect(shared.smartColorProfile == .vigilant)
        #expect(shared.updateSmartColorProfileCallCount >= 1)
    }

    @Test("init mirrors the resolved smart-color settings to the shared file")
    func initMirrorsSmartColor() {
        clean(); defer { clean() }
        let shared = MockSharedFileService()
        _ = DisplaySettingsStore(sharedFileService: shared)
        // First paint must push both values so the sandboxed widget matches.
        #expect(shared.updateSmartColorCallCount >= 1)
        #expect(shared.updateSmartColorProfileCallCount >= 1)
    }

    @Test("legacy pinned 'pacing' migrates to weeklyPacing")
    func legacyPacingPinMigrates() {
        clean(); defer { clean() }
        UserDefaults.standard.set(["fiveHour", "pacing"], forKey: "pinnedMetrics")
        let store = DisplaySettingsStore(sharedFileService: MockSharedFileService())
        #expect(store.pinnedMetrics.contains(.weeklyPacing))
        #expect(!store.pinnedMetrics.contains(where: { $0.rawValue == "pacing" }))
    }

    @Test("legacy showSessionReset=true adds the sessionReset pin")
    func legacyShowSessionResetMigrates() {
        clean(); defer { clean() }
        UserDefaults.standard.set(true, forKey: "showSessionReset")
        let store = DisplaySettingsStore(sharedFileService: MockSharedFileService())
        #expect(store.pinnedMetrics.contains(.sessionReset))
    }

    @Test("legacy smartResetColor=false is respected when smartColorEnabled is absent")
    func legacySmartResetColorRespected() {
        clean(); defer { clean() }
        UserDefaults.standard.set(false, forKey: "smartResetColor")
        let store = DisplaySettingsStore(sharedFileService: MockSharedFileService())
        #expect(store.smartColorEnabled == false)
    }

    @Test("legacy global pacingDisplayMode seeds both per-bucket modes")
    func legacyPacingDisplayModeMigrates() {
        clean(); defer { clean() }
        UserDefaults.standard.set(PacingDisplayMode.delta.rawValue, forKey: "pacingDisplayMode")
        let store = DisplaySettingsStore(sharedFileService: MockSharedFileService())
        #expect(store.sessionPacingDisplayMode == .delta)
        #expect(store.weeklyPacingDisplayMode == .delta)
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
        parent.display.menuBarStyle = .badge
        #expect(fired == true)
        _ = c
    }
}

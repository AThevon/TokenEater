import Testing
import Foundation

private let themeKeys = [
    "selectedPreset", "warningThreshold", "criticalThreshold",
    "menuBarMonochrome", "customThemeJSON"
]

private func cleanThemeDefaults() {
    for key in themeKeys {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

@Suite("ThemeStore", .serialized)
@MainActor
struct ThemeStoreTests {

    // MARK: - Helpers

    private func makeStore() -> (ThemeStore, MockSharedFileService) {
        cleanThemeDefaults()
        let mock = MockSharedFileService()
        let store = ThemeStore(sharedFileService: mock)
        return (store, mock)
    }

    // MARK: - resetToDefaults

    @Test("resetToDefaults restores all values to defaults")
    func resetToDefaultsRestoresAllValues() {
        let (store, _) = makeStore()

        store.selectedPreset = "neon"
        store.warningThreshold = 30
        store.criticalThreshold = 95
        store.menuBarMonochrome = true

        store.resetToDefaults()

        #expect(store.selectedPreset == "default")
        #expect(store.warningThreshold == 60)
        #expect(store.criticalThreshold == 85)
        #expect(store.menuBarMonochrome == false)
        #expect(store.customTheme == ThemeColors.default)
    }

    // MARK: - thresholds

    @Test("thresholds returns correct struct from current values")
    func thresholdsReturnsCorrectStruct() {
        let (store, _) = makeStore()

        store.warningThreshold = 70
        store.criticalThreshold = 90

        let t = store.thresholds
        #expect(t.warningPercent == 70)
        #expect(t.criticalPercent == 90)
    }

    // MARK: - syncToSharedFile

    @Test("syncToSharedFile calls updateTheme on shared file service")
    func syncToSharedFileCallsUpdateTheme() {
        let (store, mock) = makeStore()

        let initial = mock.updateThemeCallCount
        store.syncToSharedFile()

        #expect(mock.updateThemeCallCount == initial + 1)
    }

    // MARK: - current

    @Test("current returns default colors for default preset")
    func currentReturnsDefaultColorsForDefaultPreset() {
        let (store, _) = makeStore()

        store.resetToDefaults()

        let expected = ThemeColors.preset(for: "default")
        #expect(expected != nil)
        #expect(store.current == expected)
    }

    @Test("current returns custom theme when preset is custom")
    func currentReturnsCustomThemeWhenCustomPreset() {
        let (store, _) = makeStore()

        let neonTheme = ThemeColors.preset(for: "neon")!
        store.customTheme = neonTheme
        store.selectedPreset = "custom"

        #expect(store.current == neonTheme)
    }

    @Test("current returns neon colors for neon preset")
    func currentReturnsNeonPreset() {
        let (store, _) = makeStore()

        store.selectedPreset = "neon"

        let expected = ThemeColors.preset(for: "neon")
        #expect(store.current == expected)
    }

    // MARK: - Debounced sync

    @Test("changing warningThreshold triggers debounced sync")
    func changingThresholdTriggersDebouncedSync() async throws {
        let (store, mock) = makeStore()

        let initialCount = mock.updateThemeCallCount

        store.warningThreshold = 42

        // The debounce delay is 0.3s — wait 500ms to be safe
        try await Task.sleep(for: .milliseconds(500))

        #expect(mock.updateThemeCallCount > initialCount)
    }

    @Test("rapid changes only trigger one sync (debounce)")
    func rapidChangesDebounce() async throws {
        let (store, mock) = makeStore()

        let initialCount = mock.updateThemeCallCount

        store.warningThreshold = 30
        store.warningThreshold = 40
        store.warningThreshold = 50

        try await Task.sleep(for: .milliseconds(500))

        // Should have only synced once after the debounce, not 3 times
        #expect(mock.updateThemeCallCount == initialCount + 1)
    }

    // MARK: - menuBarMonochrome

    @Test("menuBarMonochrome persists to UserDefaults")
    func menuBarMonochromePersists() {
        let (store, _) = makeStore()

        store.menuBarMonochrome = true
        #expect(UserDefaults.standard.bool(forKey: "menuBarMonochrome") == true)

        store.menuBarMonochrome = false
        #expect(UserDefaults.standard.bool(forKey: "menuBarMonochrome") == false)
    }
}

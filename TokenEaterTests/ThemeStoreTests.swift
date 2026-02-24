import Testing
import Foundation

@Suite("ThemeStore")
@MainActor
struct ThemeStoreTests {

    // MARK: - Helpers

    private func makeStore() -> (ThemeStore, MockSharedFileService) {
        let mock = MockSharedFileService()
        let store = ThemeStore(sharedFileService: mock)
        return (store, mock)
    }

    // MARK: - resetToDefaults

    @Test("resetToDefaults restores all values to defaults")
    func resetToDefaultsRestoresAllValues() {
        let (store, _) = makeStore()

        // Change values away from defaults
        store.selectedPreset = "neon"
        store.warningThreshold = 30
        store.criticalThreshold = 95
        store.menuBarMonochrome = true

        // Reset
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

        #expect(mock.updateThemeCallCount == 0)

        store.syncToSharedFile()

        #expect(mock.updateThemeCallCount == 1)
    }

    // MARK: - current

    @Test("current returns default colors for default preset")
    func currentReturnsDefaultColorsForDefaultPreset() {
        let (store, _) = makeStore()

        store.resetToDefaults()

        let expected = ThemeColors.preset(for: "default")
        #expect(expected != nil)
        #expect(store.current == expected)
        #expect(store.current == ThemeColors.default)
    }

    // MARK: - Debounced sync

    @Test("changing warningThreshold triggers debounced sync")
    func changingThresholdTriggersDebouncedSync() async throws {
        let (store, mock) = makeStore()

        // resetToDefaults calls syncToSharedFile once, so reset the counter
        let initialCount = mock.updateThemeCallCount

        store.warningThreshold = 42

        // The debounce delay is 0.3s — wait 500ms to be safe
        try await Task.sleep(for: .milliseconds(500))

        #expect(mock.updateThemeCallCount > initialCount)
    }
}

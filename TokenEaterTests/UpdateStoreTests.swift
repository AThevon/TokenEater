import Testing
import Foundation

@Suite("UpdateStore", .serialized)
@MainActor
struct UpdateStoreTests {
    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: "brewMigrationDismissed")
    }

    // MARK: - Brew Migration

    @Test("shows brew migration when brew install detected")
    func brewMigrationDetected() {
        cleanDefaults()
        defer { cleanDefaults() }

        let mockBrew = MockBrewMigrationService()
        mockBrew.isBrewInstallResult = true
        let store = UpdateStore(
            service: MockUpdateService(),
            brewMigration: mockBrew
        )
        store.checkBrewMigration()
        #expect(store.brewMigrationState == .detected)
    }

    @Test("hides brew migration when no brew install")
    func noBrewMigration() {
        cleanDefaults()
        defer { cleanDefaults() }

        let mockBrew = MockBrewMigrationService()
        mockBrew.isBrewInstallResult = false
        let store = UpdateStore(
            service: MockUpdateService(),
            brewMigration: mockBrew
        )
        store.checkBrewMigration()
        #expect(store.brewMigrationState == .notNeeded)
    }

    @Test("dismissing brew migration persists across instances")
    func dismissBrewMigration() {
        cleanDefaults()
        defer { cleanDefaults() }

        let mockBrew = MockBrewMigrationService()
        mockBrew.isBrewInstallResult = true
        let store = UpdateStore(
            service: MockUpdateService(),
            brewMigration: mockBrew
        )
        store.checkBrewMigration()
        store.dismissBrewMigration()
        #expect(store.brewMigrationState == .dismissed)

        let store2 = UpdateStore(
            service: MockUpdateService(),
            brewMigration: mockBrew
        )
        store2.checkBrewMigration()
        #expect(store2.brewMigrationState == .dismissed)
    }

    // MARK: - Update Check

    @Test("checkForUpdates sets checking then available when update exists")
    func checkForUpdatesAvailable() async throws {
        let mockService = MockUpdateService()
        mockService.checkResult = AppcastItem(
            version: "9.9.9",
            downloadURL: URL(string: "https://example.com/test.dmg")!
        )
        let store = UpdateStore(
            service: mockService,
            brewMigration: MockBrewMigrationService()
        )
        store.checkForUpdates()

        // Wait for async task to complete
        try await Task.sleep(for: .milliseconds(100))

        #expect(mockService.checkForUpdateCalled)
        if case .available(let version, _) = store.updateState {
            #expect(version == "9.9.9")
        } else {
            Issue.record("Expected .available state, got \(store.updateState)")
        }
    }

    @Test("checkForUpdates sets upToDate when no update")
    func checkForUpdatesUpToDate() async throws {
        let mockService = MockUpdateService()
        mockService.checkResult = nil
        let store = UpdateStore(
            service: mockService,
            brewMigration: MockBrewMigrationService()
        )
        store.checkForUpdates()
        try await Task.sleep(for: .milliseconds(100))

        #expect(mockService.checkForUpdateCalled)
        #expect(store.updateState == .upToDate)
    }

    @Test("checkForUpdates sets error on failure")
    func checkForUpdatesError() async throws {
        let mockService = MockUpdateService()
        mockService.checkError = URLError(.notConnectedToInternet)
        let store = UpdateStore(
            service: mockService,
            brewMigration: MockBrewMigrationService()
        )
        store.checkForUpdates()
        try await Task.sleep(for: .milliseconds(100))

        if case .error = store.updateState {
            // OK
        } else {
            Issue.record("Expected .error state, got \(store.updateState)")
        }
    }

    // MARK: - Version Comparison

    @Test("version comparator: newer patch")
    func versionNewerPatch() {
        #expect(VersionComparator.isNewer("4.6.3", than: "4.6.2"))
        #expect(!VersionComparator.isNewer("4.6.2", than: "4.6.3"))
    }

    @Test("version comparator: release beats pre-release")
    func versionReleaseBeatsPre() {
        #expect(VersionComparator.isNewer("4.6.3", than: "4.6.3-beta.1"))
        #expect(!VersionComparator.isNewer("4.6.3-beta.1", than: "4.6.3"))
    }

    @Test("version comparator: pre-release ordering")
    func versionPreRelease() {
        #expect(VersionComparator.isNewer("4.6.3-beta.2", than: "4.6.3-beta.1"))
        #expect(VersionComparator.isNewer("4.6.3-beta.1", than: "4.6.2"))
    }

    @Test("version comparator: equal versions")
    func versionEqual() {
        #expect(!VersionComparator.isNewer("4.6.3", than: "4.6.3"))
    }

    @Test("dismiss update modal resets state")
    func dismissModal() {
        let store = UpdateStore(
            service: MockUpdateService(),
            brewMigration: MockBrewMigrationService()
        )
        store.updateState = .available(version: "9.9.9", downloadURL: URL(string: "https://example.com")!)
        store.dismissUpdateModal()
        #expect(store.updateState == .idle)
    }
}

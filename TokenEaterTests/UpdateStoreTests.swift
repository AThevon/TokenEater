import Testing
import Foundation

@Suite("UpdateStore", .serialized)
@MainActor
struct UpdateStoreTests {
    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: "brewMigrationDismissed")
    }

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

    @Test("checkForUpdates delegates to service")
    func checkForUpdates() {
        let mockService = MockUpdateService()
        let store = UpdateStore(
            service: mockService,
            brewMigration: MockBrewMigrationService()
        )
        store.checkForUpdates()
        #expect(mockService.checkForUpdatesCalled)
    }
}

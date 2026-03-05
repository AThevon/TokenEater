import Foundation

@MainActor
final class UpdateStore: ObservableObject {
    @Published var brewMigrationState: BrewMigrationState = .notNeeded
    @Published var brewUninstallCommand: String = ""

    private let service: UpdateServiceProtocol
    private let brewMigration: BrewMigrationServiceProtocol

    private var migrationDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: "brewMigrationDismissed") }
        set { UserDefaults.standard.set(newValue, forKey: "brewMigrationDismissed") }
    }

    init(
        service: UpdateServiceProtocol = UpdateService(),
        brewMigration: BrewMigrationServiceProtocol = BrewMigrationService()
    ) {
        self.service = service
        self.brewMigration = brewMigration
        self.brewUninstallCommand = brewMigration.brewUninstallCommand()
    }

    func startUpdater() {
        if let sparkle = service as? UpdateService {
            sparkle.startUpdater()
        }
    }

    func checkForUpdates() {
        service.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        service.canCheckForUpdates
    }

    func checkBrewMigration() {
        if migrationDismissed {
            brewMigrationState = .dismissed
        } else if brewMigration.isBrewInstall() {
            brewMigrationState = .detected
        } else {
            brewMigrationState = .notNeeded
        }
    }

    func dismissBrewMigration() {
        migrationDismissed = true
        brewMigrationState = .dismissed
    }
}

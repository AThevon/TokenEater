import Foundation

final class MockBrewMigrationService: BrewMigrationServiceProtocol {
    var isBrewInstallResult = false

    func isBrewInstall() -> Bool { isBrewInstallResult }
    func brewUninstallCommand() -> String { "brew uninstall --cask tokeneater" }
}

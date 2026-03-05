import Foundation

protocol BrewMigrationServiceProtocol: Sendable {
    func isBrewInstall() -> Bool
    func brewUninstallCommand() -> String
}

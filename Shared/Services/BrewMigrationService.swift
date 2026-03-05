import Foundation

final class BrewMigrationService: BrewMigrationServiceProtocol {
    private let caskroomPaths: [String]

    init(caskroomPaths: [String] = [
        "/opt/homebrew/Caskroom/tokeneater",
        "/usr/local/Caskroom/tokeneater"
    ]) {
        self.caskroomPaths = caskroomPaths
    }

    func isBrewInstall() -> Bool {
        caskroomPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    func brewUninstallCommand() -> String {
        "brew uninstall --cask tokeneater"
    }
}

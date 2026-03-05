import Testing
import Foundation

@Suite("BrewMigrationService")
struct BrewMigrationServiceTests {

    @Test("detects brew install when Caskroom directory exists")
    func detectsBrewInstall() throws {
        let testPath = "/tmp/test-caskroom-tokeneater-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: testPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: testPath) }

        let service = BrewMigrationService(caskroomPaths: [testPath])
        #expect(service.isBrewInstall() == true)
    }

    @Test("returns false when no Caskroom directory exists")
    func noBrewInstall() {
        let service = BrewMigrationService(caskroomPaths: ["/tmp/nonexistent-caskroom-\(UUID().uuidString)"])
        #expect(service.isBrewInstall() == false)
    }

    @Test("uninstall command is correct")
    func uninstallCommand() {
        let service = BrewMigrationService()
        #expect(service.brewUninstallCommand() == "brew uninstall --cask tokeneater")
    }
}

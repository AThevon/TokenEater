import Foundation

protocol UpdateServiceProtocol: Sendable {
    func checkForUpdate() async throws -> UpdateInfo?
    func launchBrewUpdate() throws
}

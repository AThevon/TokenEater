import Foundation

protocol UpdateServiceProtocol: AnyObject {
    func checkForUpdate() async throws -> AppcastItem?
    func downloadUpdate(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

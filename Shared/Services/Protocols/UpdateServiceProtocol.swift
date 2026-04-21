import Foundation

protocol UpdateServiceProtocol: AnyObject {
    func checkForUpdate() async throws -> AppcastItem?
    func downloadUpdate(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
    /// Fetch the markdown-formatted release notes for a given version from GitHub.
    /// Returns nil if the release doesn't exist or the request fails - the UI falls
    /// back to a "View on GitHub" link in that case, so this is best-effort.
    func fetchReleaseNotes(version: String) async -> String?
}

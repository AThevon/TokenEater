import Foundation

protocol UsageRepositoryProtocol {
    /// Fetches the usage and writes nothing. The store decides whether the
    /// answer still belongs to the account it reads (it may have been
    /// removed, paused or moved to another folder while the call was out)
    /// before handing it to `saveUsage`.
    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse
    /// Writes a fetched usage into the account's shared file.
    func saveUsage(_ usage: UsageResponse, fetchedAt: Date)
    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse
    func testConnection(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse
}

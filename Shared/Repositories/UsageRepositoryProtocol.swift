import Foundation

protocol UsageRepositoryProtocol {
    func refreshUsage(proxyConfig: ProxyConfig?) async throws -> UsageResponse
    func fetchProfile(proxyConfig: ProxyConfig?) async throws -> ProfileResponse
    func testConnection(proxyConfig: ProxyConfig?) async -> ConnectionTestResult
    /// Sync token from ~/.claude/.credentials.json into shared file.
    func syncCredentialsFile()
    var isConfigured: Bool { get }
    var cachedUsage: CachedUsage? { get }
    var currentToken: String? { get }
}

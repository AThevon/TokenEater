import Foundation

protocol UsageRepositoryProtocol {
    func refreshUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse
    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse
    func testConnection(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse
}

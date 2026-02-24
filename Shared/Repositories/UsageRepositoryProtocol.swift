import Foundation

protocol UsageRepositoryProtocol {
    func refreshUsage(proxyConfig: ProxyConfig?) async throws -> UsageResponse
    func testConnection(proxyConfig: ProxyConfig?) async -> ConnectionTestResult
    func syncKeychainToken()
    var isConfigured: Bool { get }
    var cachedUsage: CachedUsage? { get }
}

import Foundation

protocol UsageRepositoryProtocol {
    func refreshUsage(proxyConfig: ProxyConfig?) async throws -> UsageResponse
    func testConnection(proxyConfig: ProxyConfig?) async -> ConnectionTestResult
    /// Interactive keychain read — may trigger macOS dialog.
    func syncKeychainToken()
    /// Silent keychain read — never triggers dialog.
    func syncKeychainTokenSilently()
    var isConfigured: Bool { get }
    var cachedUsage: CachedUsage? { get }
    var currentToken: String? { get }
}

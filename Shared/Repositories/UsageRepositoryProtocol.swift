import Foundation

protocol UsageRepositoryProtocol {
    func refreshUsage(proxyConfig: ProxyConfig?) async throws -> UsageResponse
    func fetchProfile(proxyConfig: ProxyConfig?) async throws -> ProfileResponse
    func testConnection(proxyConfig: ProxyConfig?) async -> ConnectionTestResult
    /// Interactive keychain read — may trigger macOS dialog.
    func syncKeychainToken()
    /// Silent keychain read — never triggers dialog.
    func syncKeychainTokenSilently()
    /// Credentials file sync — no Keychain access at all.
    func syncCredentialsFile()
    func updateRefreshError(_ error: String)
    var isConfigured: Bool { get }
    var cachedUsage: CachedUsage? { get }
    var currentToken: String? { get }
}

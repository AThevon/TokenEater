import Foundation

final class MockUsageRepository: UsageRepositoryProtocol {
    var stubbedUsage: UsageResponse?
    var stubbedProfile: ProfileResponse?
    var stubbedProfileError: APIError?
    var stubbedError: APIError?
    var isConfiguredValue = false
    var cachedValue: CachedUsage?
    var currentTokenValue: String?

    var syncCallCount = 0
    var syncSilentCallCount = 0
    var syncCredentialsFileCallCount = 0

    var isConfigured: Bool { isConfiguredValue }
    var cachedUsage: CachedUsage? { cachedValue }
    var currentToken: String? { currentTokenValue }

    func syncKeychainToken() { syncCallCount += 1 }
    func syncKeychainTokenSilently() { syncSilentCallCount += 1 }
    func syncCredentialsFile() { syncCredentialsFileCallCount += 1 }

    func refreshUsage(proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        if let error = stubbedError { throw error }
        return stubbedUsage ?? UsageResponse()
    }

    func fetchProfile(proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
        if let error = stubbedProfileError { throw error }
        return stubbedProfile ?? .fixture()
    }

    func testConnection(proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        ConnectionTestResult(success: isConfiguredValue, message: isConfiguredValue ? "OK" : "No token")
    }
}

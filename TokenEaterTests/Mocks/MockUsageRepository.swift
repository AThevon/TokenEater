import Foundation

final class MockUsageRepository: UsageRepositoryProtocol {
    var stubbedUsage: UsageResponse?
    var shouldFail = false
    var isConfiguredValue = false
    var cachedValue: CachedUsage?
    var syncCallCount = 0

    var isConfigured: Bool { isConfiguredValue }
    var cachedUsage: CachedUsage? { cachedValue }

    func syncKeychainToken() { syncCallCount += 1 }

    func refreshUsage(proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        if shouldFail { throw APIError.invalidResponse }
        return stubbedUsage ?? UsageResponse()
    }

    func testConnection(proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        ConnectionTestResult(success: isConfiguredValue, message: isConfiguredValue ? "OK" : "No token")
    }
}

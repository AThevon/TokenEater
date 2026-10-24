import Foundation

final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    var stubbedUsage: UsageResponse?
    var stubbedProfile: ProfileResponse?
    var stubbedError: Error?
    /// Thrown by `fetchProfile` alone; `stubbedError` covers both calls.
    var stubbedProfileError: Error?
    var fetchCallCount = 0
    var fetchProfileCallCount = 0
    var lastProfileToken: String?
    var stubbedConnectionResult = ConnectionTestResult(success: true, message: "OK")

    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        fetchCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedUsage ?? UsageResponse()
    }

    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
        fetchProfileCallCount += 1
        lastProfileToken = token
        if let error = stubbedProfileError ?? stubbedError { throw error }
        return stubbedProfile ?? .fixture()
    }

    func testConnection(token: String, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        stubbedConnectionResult
    }
}

import Foundation

final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    var stubbedUsage: UsageResponse?
    var stubbedError: Error?
    var fetchCallCount = 0
    var stubbedConnectionResult = ConnectionTestResult(success: true, message: "OK")

    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        fetchCallCount += 1
        if let error = stubbedError { throw error }
        return stubbedUsage ?? UsageResponse()
    }

    func testConnection(token: String, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        stubbedConnectionResult
    }
}

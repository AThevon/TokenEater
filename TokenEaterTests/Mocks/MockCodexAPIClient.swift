import Foundation

final class MockCodexAPIClient: CodexAPIClientProtocol, @unchecked Sendable {
    var stubbedUsage: CodexUsageResponse = CodexFixtures.decode(CodexFixtures.plusJSON)
    var stubbedError: APIError?
    var stubbedTestResult = ConnectionTestResult(success: true, message: "OK")
    var fetchCount = 0
    var lastCredentials: CodexCredentials?

    func fetchUsage(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse {
        fetchCount += 1
        lastCredentials = credentials
        if let stubbedError { throw stubbedError }
        return stubbedUsage
    }

    func testConnection(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        stubbedTestResult
    }
}

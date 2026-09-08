import Foundation

final class MockCodexUsageRepository: CodexUsageRepositoryProtocol, @unchecked Sendable {
    var stubbedUsage: CodexUsageResponse = CodexFixtures.decode(CodexFixtures.plusJSON)
    var stubbedError: APIError?
    /// Consumed by the first call, so a test can fail once and then succeed
    /// (the 401-then-retry path).
    var stubbedErrorOnce: APIError?
    var stubbedTestResult = ConnectionTestResult(success: true, message: "OK")
    var onRefresh: (() async -> Void)?
    var refreshCallCount = 0
    var credentialsSeen: [CodexCredentials] = []

    func refreshUsage(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse {
        refreshCallCount += 1
        credentialsSeen.append(credentials)
        await onRefresh?()
        if let once = stubbedErrorOnce {
            stubbedErrorOnce = nil
            throw once
        }
        if let stubbedError { throw stubbedError }
        return stubbedUsage
    }

    func testConnection(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        stubbedTestResult
    }
}

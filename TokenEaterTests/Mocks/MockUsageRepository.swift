import Foundation

final class MockUsageRepository: UsageRepositoryProtocol {
    var stubbedUsage: UsageResponse?
    var stubbedProfile: ProfileResponse?
    var stubbedProfileError: Error?
    var stubbedError: Error?
    var stubbedTestError: Error?

    var refreshCallCount = 0
    var fetchProfileCallCount = 0
    var testConnectionCallCount = 0
    var lastToken: String?

    func refreshUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        refreshCallCount += 1
        lastToken = token
        if let error = stubbedError { throw error }
        return stubbedUsage ?? UsageResponse()
    }

    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
        fetchProfileCallCount += 1
        lastToken = token
        if let error = stubbedProfileError { throw error }
        return stubbedProfile ?? .fixture()
    }

    func testConnection(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        testConnectionCallCount += 1
        lastToken = token
        if let error = stubbedTestError { throw error }
        return stubbedUsage ?? UsageResponse()
    }
}

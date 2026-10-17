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

    /// Runs inside `fetchUsage` before it answers, for a test to change
    /// the store's situation while the call is out.
    var onFetchUsage: (() async -> Void)?
    var saveCallCount = 0

    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        refreshCallCount += 1
        lastToken = token
        await onFetchUsage?()
        if let error = stubbedError { throw error }
        return stubbedUsage ?? UsageResponse()
    }

    func saveUsage(_ usage: UsageResponse, fetchedAt: Date) {
        saveCallCount += 1
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

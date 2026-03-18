import Foundation

final class UsageRepository: UsageRepositoryProtocol, @unchecked Sendable {
    private let apiClient: APIClientProtocol
    private let sharedFileService: SharedFileServiceProtocol

    init(
        apiClient: APIClientProtocol = APIClient(),
        sharedFileService: SharedFileServiceProtocol = SharedFileService()
    ) {
        self.apiClient = apiClient
        self.sharedFileService = sharedFileService
    }

    func refreshUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        let usage = try await apiClient.fetchUsage(token: token, proxyConfig: proxyConfig)
        sharedFileService.updateAfterSync(
            usage: CachedUsage(usage: usage, fetchDate: Date()),
            syncDate: Date()
        )
        return usage
    }

    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
        try await apiClient.fetchProfile(token: token, proxyConfig: proxyConfig)
    }

    func testConnection(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        try await apiClient.fetchUsage(token: token, proxyConfig: proxyConfig)
    }
}

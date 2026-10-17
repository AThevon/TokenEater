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

    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        try await apiClient.fetchUsage(token: token, proxyConfig: proxyConfig)
    }

    func saveUsage(_ usage: UsageResponse, fetchedAt: Date) {
        sharedFileService.updateAfterSync(
            usage: CachedUsage(usage: usage, fetchDate: fetchedAt),
            syncDate: fetchedAt
        )
    }

    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
        try await apiClient.fetchProfile(token: token, proxyConfig: proxyConfig)
    }

    func testConnection(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        try await apiClient.fetchUsage(token: token, proxyConfig: proxyConfig)
    }
}

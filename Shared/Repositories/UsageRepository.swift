import Foundation

final class UsageRepository: UsageRepositoryProtocol {
    private let apiClient: APIClientProtocol
    private let keychainService: KeychainServiceProtocol
    private let sharedFileService: SharedFileServiceProtocol

    init(
        apiClient: APIClientProtocol = APIClient(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        sharedFileService: SharedFileServiceProtocol = SharedFileService()
    ) {
        self.apiClient = apiClient
        self.keychainService = keychainService
        self.sharedFileService = sharedFileService
    }

    func syncKeychainToken() {
        if let token = keychainService.readOAuthToken() {
            sharedFileService.oauthToken = token
        }
    }

    var isConfigured: Bool {
        sharedFileService.isConfigured
    }

    var cachedUsage: CachedUsage? {
        sharedFileService.cachedUsage
    }

    func refreshUsage(proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        guard let token = sharedFileService.oauthToken else {
            throw APIError.noToken
        }

        let usage = try await apiClient.fetchUsage(token: token, proxyConfig: proxyConfig)
        sharedFileService.updateAfterSync(
            usage: CachedUsage(usage: usage, fetchDate: Date()),
            syncDate: Date()
        )
        return usage
    }

    func testConnection(proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        guard let token = sharedFileService.oauthToken else {
            return ConnectionTestResult(success: false, message: String(localized: "error.notoken"))
        }
        return await apiClient.testConnection(token: token, proxyConfig: proxyConfig)
    }
}

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

    /// Silent keychain sync — never triggers macOS dialog.
    func syncKeychainTokenSilently() {
        if let token = keychainService.readOAuthTokenSilently() {
            sharedFileService.oauthToken = token
        }
    }

    var isConfigured: Bool {
        sharedFileService.isConfigured
    }

    var cachedUsage: CachedUsage? {
        sharedFileService.cachedUsage
    }

    var currentToken: String? {
        sharedFileService.oauthToken
    }

    /// Fetch usage with automatic token recovery on 401/403.
    /// Silent keychain read → different token? update + retry once. Otherwise rethrow.
    func refreshUsage(proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        guard let token = sharedFileService.oauthToken else {
            throw APIError.noToken
        }

        do {
            let usage = try await apiClient.fetchUsage(token: token, proxyConfig: proxyConfig)
            sharedFileService.updateAfterSync(
                usage: CachedUsage(usage: usage, fetchDate: Date()),
                syncDate: Date()
            )
            return usage
        } catch APIError.tokenExpired {
            return try await attemptSilentTokenRecovery(proxyConfig: proxyConfig)
        }
    }

    func testConnection(proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        guard let token = sharedFileService.oauthToken else {
            return ConnectionTestResult(success: false, message: String(localized: "error.notoken"))
        }
        return await apiClient.testConnection(token: token, proxyConfig: proxyConfig)
    }

    // MARK: - Private

    private func attemptSilentTokenRecovery(proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        let currentToken = sharedFileService.oauthToken

        guard let freshToken = keychainService.readOAuthTokenSilently() else {
            // Keychain inaccessible (locked or needs auth). Keep current token, retry next cycle.
            throw APIError.keychainLocked
        }

        guard freshToken != currentToken else {
            // Same token in keychain — Claude Code hasn't refreshed yet.
            throw APIError.tokenExpired
        }

        // Claude Code auto-refreshed the token — update and retry once
        sharedFileService.oauthToken = freshToken
        let usage = try await apiClient.fetchUsage(token: freshToken, proxyConfig: proxyConfig)
        sharedFileService.updateAfterSync(
            usage: CachedUsage(usage: usage, fetchDate: Date()),
            syncDate: Date()
        )
        return usage
    }
}

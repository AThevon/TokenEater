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

    /// Sync token from ~/.claude/.credentials.json into shared file.
    func syncCredentialsFile() {
        if let token = keychainService.readToken(), token != sharedFileService.oauthToken {
            sharedFileService.oauthToken = token
        }
    }

    /// Silent Keychain sync — for boot/onboarding only. Never triggers a dialog.
    func syncKeychainSilently() {
        if let token = keychainService.readKeychainTokenSilently(), token != sharedFileService.oauthToken {
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
    /// Reads credentials file to check if Claude Code refreshed the token, then retries once.
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
            return try await attemptTokenRecovery(proxyConfig: proxyConfig)
        }
    }

    func fetchProfile(proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
        guard let token = sharedFileService.oauthToken else {
            throw APIError.noToken
        }
        return try await apiClient.fetchProfile(token: token, proxyConfig: proxyConfig)
    }

    func testConnection(proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        guard let token = sharedFileService.oauthToken else {
            return ConnectionTestResult(success: false, message: String(localized: "error.notoken"))
        }
        return await apiClient.testConnection(token: token, proxyConfig: proxyConfig)
    }

    // MARK: - Private

    private func attemptTokenRecovery(proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        let currentToken = sharedFileService.oauthToken

        guard let freshToken = keychainService.readToken() else {
            // Credentials file unavailable. Keep current token, retry next cycle.
            throw APIError.keychainLocked
        }

        guard freshToken != currentToken else {
            // Same token in credentials file — Claude Code hasn't refreshed yet.
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

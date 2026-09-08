import Foundation

/// Fetches Codex usage, then persists it for the widget. Same two-step shape as
/// `UsageRepository`, so the store never touches the shared file directly.
final class CodexUsageRepository: CodexUsageRepositoryProtocol, @unchecked Sendable {

    // MARK: - Private Properties

    private let apiClient: CodexAPIClientProtocol
    private let sharedFileService: CodexSharedFileServiceProtocol

    // MARK: - Initializers

    init(
        apiClient: CodexAPIClientProtocol = CodexAPIClient(),
        sharedFileService: CodexSharedFileServiceProtocol = CodexSharedFileService()
    ) {
        self.apiClient = apiClient
        self.sharedFileService = sharedFileService
    }

    // MARK: - CodexUsageRepositoryProtocol

    func refreshUsage(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse {
        let usage = try await apiClient.fetchUsage(credentials: credentials, proxyConfig: proxyConfig)
        try Task.checkCancellation()
        sharedFileService.updateAfterSync(
            usage: CachedCodexUsage(usage: usage, fetchDate: Date()),
            syncDate: Date()
        )
        return usage
    }

    func testConnection(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        await apiClient.testConnection(credentials: credentials, proxyConfig: proxyConfig)
    }
}

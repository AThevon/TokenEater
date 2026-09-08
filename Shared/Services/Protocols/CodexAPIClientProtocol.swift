import Foundation

protocol CodexAPIClientProtocol: Sendable {
    func fetchUsage(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse
    func testConnection(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async -> ConnectionTestResult
}

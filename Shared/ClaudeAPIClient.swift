import Foundation

final class ClaudeAPIClient {
    static let shared = ClaudeAPIClient()

    private let oauthURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Set by host app (from UserDefaults)
    var proxyConfig: ProxyConfig?

    private var session: URLSession {
        guard let proxy = proxyConfig, proxy.enabled else { return .shared }
        let c = URLSessionConfiguration.default
        c.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable as String: true,
            kCFNetworkProxiesSOCKSProxy as String: proxy.host,
            kCFNetworkProxiesSOCKSPort as String: proxy.port,
        ]
        return URLSession(configuration: c)
    }

    // MARK: - Auth

    var isConfigured: Bool {
        SharedContainer.isConfigured
    }

    // MARK: - Fetch Usage (with recovery)

    /// Fetch usage with automatic token recovery on 401/403.
    /// Silent keychain read → different token? update + retry once. Otherwise throw.
    func fetchUsageWithRecovery() async throws -> UsageResponse {
        do {
            return try await fetchUsage()
        } catch ClaudeAPIError.tokenExpired {
            return try await attemptSilentTokenRecovery()
        }
    }

    private func attemptSilentTokenRecovery() async throws -> UsageResponse {
        let currentToken = SharedContainer.oauthToken

        guard let credentials = KeychainOAuthReader.readClaudeCodeTokenSilently() else {
            // Keychain inaccessible (locked or needs auth).
            // Keep current token — it may work once keychain unlocks. Retry next cycle.
            throw ClaudeAPIError.keychainLocked
        }

        guard credentials.accessToken != currentToken else {
            // Same token in keychain — Claude Code hasn't refreshed yet.
            // Keep it cached, let the ViewModel track the failed state.
            throw ClaudeAPIError.tokenExpired
        }

        // Claude Code auto-refreshed the token — update and retry once
        SharedContainer.oauthToken = credentials.accessToken
        return try await fetchUsage()
    }

    // MARK: - Fetch Usage (raw)

    func fetchUsage() async throws -> UsageResponse {
        guard let token = SharedContainer.oauthToken else {
            throw ClaudeAPIError.noToken
        }

        var request = URLRequest(url: oauthURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
            SharedContainer.updateAfterSync(
                usage: CachedUsage(usage: usage, fetchDate: Date()),
                syncDate: Date()
            )
            return usage
        case 401, 403:
            throw ClaudeAPIError.tokenExpired
        default:
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - Test Connection

    func testConnection() async -> ConnectionTestResult {
        guard let token = SharedContainer.oauthToken else {
            return ConnectionTestResult(success: false, message: String(localized: "error.notoken"))
        }

        var request = URLRequest(url: oauthURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return ConnectionTestResult(success: false, message: String(localized: "error.invalidresponse.short"))
            }

            if httpResponse.statusCode == 200 {
                guard let usage = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
                    return ConnectionTestResult(success: false, message: String(localized: "error.unsupportedplan"))
                }
                let sessionPct = usage.fiveHour?.utilization ?? 0
                return ConnectionTestResult(success: true, message: String(format: String(localized: "test.success"), Int(sessionPct)))
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return ConnectionTestResult(success: false, message: String(format: String(localized: "test.expired"), httpResponse.statusCode))
            } else {
                return ConnectionTestResult(success: false, message: String(format: String(localized: "test.http"), httpResponse.statusCode))
            }
        } catch {
            return ConnectionTestResult(success: false, message: String(format: String(localized: "error.network"), error.localizedDescription))
        }
    }

    // MARK: - Cache

    func loadCachedUsage() -> CachedUsage? {
        SharedContainer.cachedUsage
    }
}

// MARK: - Error

enum ClaudeAPIError: LocalizedError {
    case noToken
    case invalidResponse
    case tokenExpired
    case keychainLocked
    case unsupportedPlan
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return String(localized: "error.notoken")
        case .invalidResponse:
            return String(localized: "error.invalidresponse")
        case .tokenExpired:
            return String(localized: "error.tokenexpired")
        case .keychainLocked:
            return String(localized: "error.keychainlocked")
        case .unsupportedPlan:
            return String(localized: "error.unsupportedplan")
        case .httpError(let code):
            return String(format: String(localized: "error.http"), code)
        }
    }
}

// MARK: - Test Result

struct ConnectionTestResult {
    let success: Bool
    let message: String
}

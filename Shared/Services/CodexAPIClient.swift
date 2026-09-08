import Foundation

/// Client for the single Codex endpoint TokenEater calls.
///
/// The endpoint is the same one the Codex TUI polls for its own `/status`
/// display. A plain `User-Agent` is deliberate: impersonating `codex_cli_rs`
/// (and sending an `originator` header) is what has been reported to attract
/// Cloudflare challenges, while an honest UA answers 200.
final class CodexAPIClient: CodexAPIClientProtocol, @unchecked Sendable {

    // MARK: - Private Properties

    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// Session factory, injected so tests can stub the transport. Production
    /// hands back the shared proxy-aware session.
    private let sessionProvider: @Sendable (ProxyConfig?) -> URLSession

    private let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return "TokenEater/\(version)"
    }()

    // MARK: - Initializers

    init(sessionProvider: @escaping @Sendable (ProxyConfig?) -> URLSession = { URLSession.tokenEater(proxyConfig: $0) }) {
        self.sessionProvider = sessionProvider
    }

    // MARK: - CodexAPIClientProtocol

    func fetchUsage(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse {
        let endpoint = usageURL.path
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await sessionProvider(proxyConfig)
                .data(for: makeRequest(credentials: credentials))
        } catch {
            throw APIError.networkError(endpoint: endpoint, underlying: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(endpoint: endpoint)
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            } catch {
                throw APIError.invalidResponse(endpoint: endpoint)
            }
        case 401, 403:
            // An invalid or expired bearer answers 401 here, with the error body
            // arriving as `application/json` or `text/plain` depending on which
            // layer rejected it - so the status code is the only reliable
            // signal and the content type is never inspected.
            throw APIError.tokenExpired(endpoint: endpoint, statusCode: httpResponse.statusCode)
        case 429:
            let retryAfterRaw = httpResponse.value(forHTTPHeaderField: "Retry-After")
            let retryAfter = retryAfterRaw.flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter, retryAfterRaw: retryAfterRaw, endpoint: endpoint)
        default:
            throw APIError.httpError(statusCode: httpResponse.statusCode, endpoint: endpoint)
        }
    }

    func testConnection(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        do {
            let usage = try await fetchUsage(credentials: credentials, proxyConfig: proxyConfig)
            guard let window = CodexWindowResolver.windows(in: usage).first else {
                return ConnectionTestResult(success: true, message: String(localized: "codex.test.noWindows"))
            }
            return ConnectionTestResult(
                success: true,
                message: String(format: String(localized: "codex.test.success"), window.label, window.pct)
            )
        } catch let error as APIError {
            switch error {
            case .rateLimited:
                return ConnectionTestResult(success: true, message: String(localized: "test.ratelimited"))
            case .tokenExpired(_, let statusCode):
                return ConnectionTestResult(success: false, message: String(format: String(localized: "test.expired"), statusCode))
            default:
                return ConnectionTestResult(success: false, message: error.localizedDescription)
            }
        } catch {
            return ConnectionTestResult(success: false, message: error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    private func makeRequest(credentials: CodexCredentials) -> URLRequest {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        // Optional for a single-account login, required to disambiguate a
        // workspace membership. Codex always sends it.
        if let accountId = credentials.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}

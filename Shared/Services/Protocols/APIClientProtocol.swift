import Foundation

enum APIError: LocalizedError {
    case noToken
    case invalidResponse(endpoint: String)
    case tokenExpired(endpoint: String, statusCode: Int)
    case unsupportedPlan
    case rateLimited(retryAfter: TimeInterval?, retryAfterRaw: String?, endpoint: String)
    case httpError(statusCode: Int, endpoint: String)
    case networkError(endpoint: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return String(localized: "error.notoken")
        case .invalidResponse:
            return String(localized: "error.invalidresponse")
        case .tokenExpired:
            return String(localized: "error.tokenexpired")
        case .unsupportedPlan:
            return String(localized: "error.unsupportedplan")
        case .rateLimited:
            return String(localized: "error.ratelimited")
        case .httpError(let code, _):
            return String(format: String(localized: "error.http"), code)
        case .networkError(_, let underlying):
            return String(format: String(localized: "error.network"), underlying)
        }
    }

    /// Diagnostic snapshot of this error, used by the "Copy diagnostic" button.
    /// Returns nil for cases that carry no transport-level info (noToken, unsupportedPlan).
    var diagnosticSnapshot: LastAPIError? {
        switch self {
        case .noToken, .unsupportedPlan:
            return nil
        case .invalidResponse(let endpoint):
            return LastAPIError(
                httpStatusCode: nil,
                retryAfterHeader: nil,
                endpoint: endpoint,
                timestamp: Date(),
                underlyingError: "response body could not be decoded"
            )
        case .tokenExpired(let endpoint, let statusCode):
            return LastAPIError(
                httpStatusCode: statusCode,
                retryAfterHeader: nil,
                endpoint: endpoint,
                timestamp: Date(),
                underlyingError: nil
            )
        case .rateLimited(_, let retryAfterRaw, let endpoint):
            return LastAPIError(
                httpStatusCode: 429,
                retryAfterHeader: retryAfterRaw,
                endpoint: endpoint,
                timestamp: Date(),
                underlyingError: nil
            )
        case .httpError(let statusCode, let endpoint):
            return LastAPIError(
                httpStatusCode: statusCode,
                retryAfterHeader: nil,
                endpoint: endpoint,
                timestamp: Date(),
                underlyingError: nil
            )
        case .networkError(let endpoint, let underlying):
            return LastAPIError(
                httpStatusCode: nil,
                retryAfterHeader: nil,
                endpoint: endpoint,
                timestamp: Date(),
                underlyingError: underlying
            )
        }
    }
}

struct ConnectionTestResult {
    let success: Bool
    let message: String
}

protocol APIClientProtocol: Sendable {
    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse
    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse
    func testConnection(token: String, proxyConfig: ProxyConfig?) async -> ConnectionTestResult
}

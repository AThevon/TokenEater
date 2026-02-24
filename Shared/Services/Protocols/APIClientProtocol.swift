import Foundation

enum APIError: LocalizedError {
    case noToken
    case invalidResponse
    case tokenExpired
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
        case .unsupportedPlan:
            return String(localized: "error.unsupportedplan")
        case .httpError(let code):
            return String(format: String(localized: "error.http"), code)
        }
    }
}

struct ConnectionTestResult {
    let success: Bool
    let message: String
}

protocol APIClientProtocol: Sendable {
    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse
    func testConnection(token: String, proxyConfig: ProxyConfig?) async -> ConnectionTestResult
}

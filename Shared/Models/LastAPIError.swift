import Foundation

/// Snapshot of the most recent API failure, captured in-memory by `UsageStore`
/// so the diagnostic report can show the raw server response details.
/// Not persisted. Reset to nil on successful refresh.
struct LastAPIError {
    /// HTTP status code from the response. nil when the request never got a response (network error).
    let httpStatusCode: Int?
    /// Raw `Retry-After` header value as returned by the server, before any interpretation.
    let retryAfterHeader: String?
    /// Endpoint path that failed, e.g. "/api/oauth/usage" or "/api/oauth/profile".
    let endpoint: String
    /// When the error was captured.
    let timestamp: Date
    /// `localizedDescription` of an underlying URLError or decoding error, if any.
    let underlyingError: String?
}

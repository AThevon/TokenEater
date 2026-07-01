import Foundation

enum StatusServiceError: Error {
    case badResponse
}

/// Atlassian Statuspage v2 client.
final class StatusService: StatusServiceProtocol, @unchecked Sendable {
    func fetchStatus(for vendor: Vendor) async throws -> VendorStatus {
        let url = vendor.statusAPIBaseURL.appendingPathComponent("summary.json")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw StatusServiceError.badResponse
        }
        let summary = try JSONDecoder().decode(StatuspageSummary.self, from: data)
        return VendorStatus.from(summary: summary, vendor: vendor, now: Date())
    }
}

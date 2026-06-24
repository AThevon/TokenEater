import Foundation

final class MockStatusService: StatusServiceProtocol {
    var stubbedStatus: VendorStatus?
    var stubbedError: Error?
    private(set) var fetchCallCount = 0

    func fetchStatus(for vendor: Vendor) async throws -> VendorStatus {
        fetchCallCount += 1
        if let stubbedError { throw stubbedError }
        if let stubbedStatus { return stubbedStatus }
        throw StatusServiceError.badResponse
    }
}

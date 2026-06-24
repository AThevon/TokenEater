import Foundation

protocol StatusServiceProtocol {
    /// Fetch and map the current status for a vendor. Throws on network or
    /// decode failure; callers must treat a throw as "unknown", never "down".
    func fetchStatus(for vendor: Vendor) async throws -> VendorStatus
}

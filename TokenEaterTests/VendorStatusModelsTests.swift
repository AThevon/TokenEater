import Testing
import Foundation

@Suite("VendorStatusModels")
struct VendorStatusModelsTests {

    @Test("VendorHealth maps component statuses")
    func healthMapping() {
        #expect(VendorHealth.from(componentStatus: "operational") == .healthy)
        #expect(VendorHealth.from(componentStatus: "degraded_performance") == .degraded)
        #expect(VendorHealth.from(componentStatus: "partial_outage") == .degraded)
        #expect(VendorHealth.from(componentStatus: "under_maintenance") == .degraded)
        #expect(VendorHealth.from(componentStatus: "major_outage") == .down)
        #expect(VendorHealth.from(componentStatus: "anything_unknown") == .healthy)
    }

    @Test("VendorHealth is ordered healthy < degraded < down")
    func healthOrdering() {
        #expect(VendorHealth.healthy < VendorHealth.degraded)
        #expect(VendorHealth.degraded < VendorHealth.down)
        #expect([VendorHealth.healthy, .down, .degraded].max() == .down)
    }

    @Test("Claude vendor exposes the canonical status host")
    func claudeURLs() {
        #expect(Vendor.claude.statusAPIBaseURL.absoluteString == "https://status.claude.com/api/v2")
        #expect(Vendor.claude.statusPageURL.absoluteString == "https://status.claude.com")
        #expect(Vendor.claude.displayName == "Claude")
    }
}

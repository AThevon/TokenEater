import Testing
import Foundation

@Suite("Vendor outage notifications", .serialized)
@MainActor
struct VendorOutageNotificationTests {

    private func clearState() {
        UserDefaults.standard.removeObject(forKey: "lastVendorHealth_claude")
    }

    /// Inject mocks so construction never touches the real UNUserNotificationCenter,
    /// which throws in the xctest host (no bundle). checkVendorHealth persists the
    /// health to UserDefaults directly, which is what these tests assert on.
    private func makeService() -> NotificationService {
        NotificationService(center: MockNotificationCenter(), stateStore: MockNotificationStateStore())
    }

    private func toggles(degraded: Bool = true, restored: Bool = true, master: Bool = true) -> NotificationToggles {
        NotificationToggles(
            masterEnabled: master,
            trackFiveHour: true, trackWeekly: true, trackSonnet: true, trackDesign: true,
            sendRecovery: true, pacingHot: true, pacingWarning: false,
            resetReminderSession: false, resetReminderWeekly: false,
            resetReminderSessionOffsetMinutes: 15, resetReminderWeeklyOffsetMinutes: 60,
            extraCredits: true, tokenExpired: true,
            smartColorEnabled: false, smartColorProfile: .default, pacingMargin: 10,
            thresholds: .default,
            vendorDegraded: degraded, vendorRestored: restored
        )
    }

    private func status(_ health: VendorHealth, maintenance: Bool = false) -> VendorStatus {
        VendorStatus(
            vendor: .claude, health: health, affectedComponents: [],
            activeIncidents: [], lastChecked: Date(), isStale: false,
            isMaintenanceOnly: maintenance
        )
    }

    @Test("persists last health on a healthy->degraded edge")
    func edgePersists() {
        clearState()
        let service = makeService()
        // healthy is the implicit default (key absent == 0 == healthy).
        service.checkVendorHealth(status(.degraded), toggles: toggles())
        #expect(UserDefaults.standard.integer(forKey: "lastVendorHealth_claude") == VendorHealth.degraded.rawValue)
    }

    @Test("no state change when health is unchanged")
    func noChange() {
        clearState()
        UserDefaults.standard.set(VendorHealth.down.rawValue, forKey: "lastVendorHealth_claude")
        let service = makeService()
        service.checkVendorHealth(status(.down), toggles: toggles())
        #expect(UserDefaults.standard.integer(forKey: "lastVendorHealth_claude") == VendorHealth.down.rawValue)
    }

    @Test("maintenance-only degradation does NOT advance persisted health")
    func maintenanceSuppressed() {
        clearState()
        let service = makeService()
        service.checkVendorHealth(status(.degraded, maintenance: true), toggles: toggles())
        // Not persisted -> stays at healthy(0), so no phantom 'restored' later.
        #expect(UserDefaults.standard.integer(forKey: "lastVendorHealth_claude") == VendorHealth.healthy.rawValue)
    }

    @Test("master off is a no-op")
    func masterOff() {
        clearState()
        let service = makeService()
        service.checkVendorHealth(status(.down), toggles: toggles(master: false))
        #expect(UserDefaults.standard.integer(forKey: "lastVendorHealth_claude") == VendorHealth.healthy.rawValue)
    }
}

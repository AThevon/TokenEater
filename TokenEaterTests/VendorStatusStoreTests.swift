import Testing
import Foundation

@Suite("VendorStatusStore")
@MainActor
struct VendorStatusStoreTests {

    private func toggles() -> NotificationToggles {
        NotificationToggles(
            masterEnabled: true,
            trackFiveHour: true, trackWeekly: true, trackSonnet: true, trackDesign: true,
            sendRecovery: true, pacingHot: true, pacingWarning: false,
            resetReminderSession: false, resetReminderWeekly: false,
            resetReminderSessionOffsetMinutes: 15, resetReminderWeeklyOffsetMinutes: 60,
            extraCredits: true, tokenExpired: true,
            smartColorEnabled: false, smartColorProfile: .default, pacingMargin: 10,
            thresholds: .default,
            vendorDegraded: true, vendorRestored: true
        )
    }

    private func status(_ health: VendorHealth) -> VendorStatus {
        VendorStatus(
            vendor: .claude, health: health, affectedComponents: [],
            activeIncidents: [], lastChecked: Date(), isStale: false, isMaintenanceOnly: false
        )
    }

    @Test("poll cadence accelerates during an outage")
    func cadence() {
        #expect(VendorStatusStore.pollInterval(forHealth: .healthy, healthyInterval: 300) == 300)
        #expect(VendorStatusStore.pollInterval(forHealth: .degraded, healthyInterval: 300) == 60)
        #expect(VendorStatusStore.pollInterval(forHealth: .down, healthyInterval: 300) == 60)
    }

    @Test("pollOnce publishes fetched status and notifies")
    func pollPublishes() async {
        let svc = MockStatusService()
        svc.stubbedStatus = status(.down)
        let notif = MockNotificationService()
        let store = VendorStatusStore(statusService: svc, notificationService: notif)
        store.notifTogglesProvider = { [self] in toggles() }

        await store.pollOnce()

        #expect(store.claudeStatus?.health == .down)
        #expect(store.isDegraded == true)
        #expect(store.worstHealth == .down)
        #expect(notif.vendorHealthChecks.count == 1)
        #expect(notif.vendorHealthChecks.first?.status.health == .down)
    }

    @Test("a fetch failure keeps last-known status and marks it stale")
    func staleOnFailure() async {
        let svc = MockStatusService()
        svc.stubbedStatus = status(.degraded)
        let notif = MockNotificationService()
        let store = VendorStatusStore(statusService: svc, notificationService: notif)
        store.notifTogglesProvider = { [self] in toggles() }

        await store.pollOnce()
        #expect(store.claudeStatus?.health == .degraded)
        #expect(store.claudeStatus?.isStale == false)

        svc.stubbedStatus = nil
        svc.stubbedError = StatusServiceError.badResponse
        await store.pollOnce()

        // Health unchanged, but flagged stale; no extra notification fired.
        #expect(store.claudeStatus?.health == .degraded)
        #expect(store.claudeStatus?.isStale == true)
        #expect(notif.vendorHealthChecks.count == 1)
    }
}

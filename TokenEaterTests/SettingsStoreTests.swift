import Testing
import Foundation
import UserNotifications

private let settingsKeys = [
    "showMenuBar", "pinnedMetrics", "pacingDisplayMode",
    "hasCompletedOnboarding", "proxyEnabled", "proxyHost", "proxyPort",
    "overlayEnabled", "watcherStyle"
]

private func cleanDefaults() {
    for key in settingsKeys {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

@Suite("SettingsStore", .serialized)
@MainActor
struct SettingsStoreTests {

    // MARK: - Helpers

    private func makeStore(
        keychain: MockKeychainService = MockKeychainService()
    ) -> (SettingsStore, MockNotificationService, MockKeychainService) {
        cleanDefaults()
        let notif = MockNotificationService()
        let store = SettingsStore(notificationService: notif, keychainService: keychain)
        return (store, notif, keychain)
    }

    // MARK: - Proxy Config

    @Test("proxyConfig reflects current values")
    func proxyConfigReflectsValues() {
        let (store, _, _) = makeStore()
        store.proxyEnabled = true
        store.proxyHost = "10.0.0.1"
        store.proxyPort = 8080

        let config = store.proxyConfig
        #expect(config.enabled == true)
        #expect(config.host == "10.0.0.1")
        #expect(config.port == 8080)
    }

    @Test("proxyConfig returns defaults on fresh store")
    func proxyConfigDefaults() {
        let (store, _, _) = makeStore()

        let config = store.proxyConfig
        #expect(config.enabled == false)
        #expect(config.host == "127.0.0.1")
        #expect(config.port == 1080)
    }

    // MARK: - Toggle Metric

    @Test("toggleMetric adds a metric not in the set")
    func toggleMetricAdds() {
        let (store, _, _) = makeStore()
        #expect(!store.pinnedMetrics.contains(.sonnet))

        store.toggleMetric(.sonnet)
        #expect(store.pinnedMetrics.contains(.sonnet))
    }

    @Test("toggleMetric removes metric when count > 1")
    func toggleMetricRemoves() {
        let (store, _, _) = makeStore()
        #expect(store.pinnedMetrics.count == 2)
        #expect(store.pinnedMetrics.contains(.fiveHour))

        store.toggleMetric(.fiveHour)
        #expect(!store.pinnedMetrics.contains(.fiveHour))
    }

    @Test("toggleMetric does not remove last metric")
    func toggleMetricKeepsLast() {
        let (store, _, _) = makeStore()
        store.pinnedMetrics = [.sonnet]
        #expect(store.pinnedMetrics.count == 1)

        store.toggleMetric(.sonnet)
        #expect(store.pinnedMetrics.contains(.sonnet))
        #expect(store.pinnedMetrics.count == 1)
    }

    @Test("toggleMetric works with .pacing")
    func toggleMetricPacing() {
        let (store, _, _) = makeStore()
        #expect(!store.pinnedMetrics.contains(.pacing))

        store.toggleMetric(.pacing)
        #expect(store.pinnedMetrics.contains(.pacing))

        store.toggleMetric(.pacing)
        // Still has other metrics, so pacing should be removed
        #expect(!store.pinnedMetrics.contains(.pacing))
    }

    // MARK: - Credentials delegation

    @Test("credentialsTokenExists delegates to service")
    func credentialsTokenExistsDelegates() {
        let keychain = MockKeychainService()
        keychain.storedToken = "some-token"
        let (store, _, _) = makeStore(keychain: keychain)

        #expect(store.credentialsTokenExists() == true)
    }

    @Test("credentialsTokenExists returns false when no token")
    func credentialsTokenExistsFalseWhenNoToken() {
        let (store, _, _) = makeStore()

        #expect(store.credentialsTokenExists() == false)
    }

    // MARK: - Notification delegation

    @Test("requestNotificationPermission delegates to service")
    func requestNotificationPermissionDelegates() {
        let (store, notif, _) = makeStore()

        store.requestNotificationPermission()

        #expect(notif.permissionRequested == true)
    }

    @Test("sendTestNotification delegates to service")
    func sendTestNotificationDelegates() {
        let (store, notif, _) = makeStore()

        store.sendTestNotification()

        #expect(notif.testSent == true)
    }

    @Test("refreshNotificationStatus updates status from service")
    func refreshNotificationStatusUpdates() async {
        let (store, notif, _) = makeStore()
        notif.stubbedAuthStatus = .authorized

        await store.refreshNotificationStatus()

        #expect(store.notificationStatus == .authorized)
    }

    // MARK: - Persistence

    @Test("hasCompletedOnboarding persists to UserDefaults")
    func hasCompletedOnboardingPersists() {
        let (store, _, _) = makeStore()

        store.hasCompletedOnboarding = true
        #expect(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") == true)
    }

    @Test("pinnedMetrics persists to UserDefaults")
    func pinnedMetricsPersists() {
        let (store, _, _) = makeStore()

        store.pinnedMetrics = [.sonnet, .pacing]

        let saved = UserDefaults.standard.stringArray(forKey: "pinnedMetrics") ?? []
        #expect(saved.contains("sonnet"))
        #expect(saved.contains("pacing"))
    }

    // MARK: - Overlay

    @Test("overlayEnabled defaults to true")
    func overlayEnabledDefaults() {
        let (store, _, _) = makeStore()
        #expect(store.overlayEnabled == true)
    }

    @Test("overlayEnabled persists to UserDefaults")
    func overlayEnabledPersists() {
        let (store, _, _) = makeStore()
        store.overlayEnabled = false
        #expect(UserDefaults.standard.object(forKey: "overlayEnabled") as? Bool == false)
    }

    // MARK: - Watcher Style

    @Test("watcherStyle defaults to frost")
    func watcherStyleDefaults() {
        let (store, _, _) = makeStore()
        #expect(store.watcherStyle == .frost)
    }

    @Test("watcherStyle persists to UserDefaults")
    func watcherStylePersists() {
        let (store, _, _) = makeStore()
        store.watcherStyle = .neon
        #expect(UserDefaults.standard.string(forKey: "watcherStyle") == "neon")
    }

    @Test("watcherStyle reads from UserDefaults on init")
    func watcherStyleReadsFromDefaults() {
        cleanDefaults()
        UserDefaults.standard.set("neon", forKey: "watcherStyle")
        let notif = MockNotificationService()
        let store = SettingsStore(notificationService: notif, keychainService: MockKeychainService())
        #expect(store.watcherStyle == .neon)
    }

    @Test("watcherStyle falls back to frost on invalid value")
    func watcherStyleFallsBackOnInvalid() {
        cleanDefaults()
        UserDefaults.standard.set("cyberpunk", forKey: "watcherStyle")
        let notif = MockNotificationService()
        let store = SettingsStore(notificationService: notif, keychainService: MockKeychainService())
        #expect(store.watcherStyle == .frost)
    }

}

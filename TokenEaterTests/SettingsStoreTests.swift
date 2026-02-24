import Testing
import Foundation

@MainActor
@Suite("SettingsStore")
struct SettingsStoreTests {

    // Clean UserDefaults before each test to avoid cross-test pollution
    private static let settingsKeys = [
        "showMenuBar", "pinnedMetrics", "pacingDisplayMode",
        "hasCompletedOnboarding", "proxyEnabled", "proxyHost", "proxyPort"
    ]

    private func cleanDefaults() {
        for key in Self.settingsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Proxy Config

    @Test("proxyConfig reflects current values")
    func proxyConfigReflectsValues() {
        cleanDefaults()
        let store = SettingsStore(
            notificationService: MockNotificationService(),
            keychainService: MockKeychainService()
        )
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
        cleanDefaults()
        let store = SettingsStore(
            notificationService: MockNotificationService(),
            keychainService: MockKeychainService()
        )

        let config = store.proxyConfig
        #expect(config.enabled == false)
        #expect(config.host == "127.0.0.1")
        #expect(config.port == 1080)
    }

    // MARK: - Toggle Metric

    @Test("toggleMetric adds a metric not in the set")
    func toggleMetricAdds() {
        cleanDefaults()
        let store = SettingsStore(
            notificationService: MockNotificationService(),
            keychainService: MockKeychainService()
        )
        // Default pinnedMetrics = [.fiveHour, .sevenDay]
        #expect(!store.pinnedMetrics.contains(.sonnet))

        store.toggleMetric(.sonnet)
        #expect(store.pinnedMetrics.contains(.sonnet))
    }

    @Test("toggleMetric removes metric when count > 1")
    func toggleMetricRemoves() {
        cleanDefaults()
        let store = SettingsStore(
            notificationService: MockNotificationService(),
            keychainService: MockKeychainService()
        )
        // Default has 2 metrics: .fiveHour and .sevenDay
        #expect(store.pinnedMetrics.count == 2)
        #expect(store.pinnedMetrics.contains(.fiveHour))

        store.toggleMetric(.fiveHour)
        #expect(!store.pinnedMetrics.contains(.fiveHour))
    }

    @Test("toggleMetric does not remove last metric")
    func toggleMetricKeepsLast() {
        cleanDefaults()
        let store = SettingsStore(
            notificationService: MockNotificationService(),
            keychainService: MockKeychainService()
        )
        // Reduce to a single metric
        store.pinnedMetrics = [.sonnet]
        #expect(store.pinnedMetrics.count == 1)

        store.toggleMetric(.sonnet)
        #expect(store.pinnedMetrics.contains(.sonnet))
        #expect(store.pinnedMetrics.count == 1)
    }

    // MARK: - Keychain delegation

    @Test("keychainTokenExists delegates to service")
    func keychainTokenExistsDelegates() {
        cleanDefaults()
        let mockKeychain = MockKeychainService()
        mockKeychain.storedToken = "some-token"
        let store = SettingsStore(
            notificationService: MockNotificationService(),
            keychainService: mockKeychain
        )

        #expect(store.keychainTokenExists() == true)
    }

    @Test("readKeychainToken delegates to service")
    func readKeychainTokenDelegates() {
        cleanDefaults()
        let mockKeychain = MockKeychainService()
        mockKeychain.storedToken = "abc"
        let store = SettingsStore(
            notificationService: MockNotificationService(),
            keychainService: mockKeychain
        )

        #expect(store.readKeychainToken() == "abc")
    }
}

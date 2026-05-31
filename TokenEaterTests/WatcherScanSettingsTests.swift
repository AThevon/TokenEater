import Testing
import Foundation

@Suite("WatcherScanInterval / WatcherVisibility")
struct WatcherScanSettingsTests {

    @Test("scan interval seconds match raw values and there is no sub-2s option")
    func scanIntervalSeconds() {
        #expect(WatcherScanInterval.twoSeconds.seconds == 2)
        #expect(WatcherScanInterval.fiveSeconds.seconds == 5)
        #expect(WatcherScanInterval.tenSeconds.seconds == 10)
        #expect(WatcherScanInterval.allCases.map(\.rawValue).min() == 2)
    }

    @Test("scan interval labels are compact")
    func scanIntervalLabels() {
        #expect(WatcherScanInterval.twoSeconds.label == "2s")
        #expect(WatcherScanInterval.tenSeconds.label == "10s")
    }

    @Test("visibility seconds cover 30 min through 7 days, no 'always'")
    func visibilitySeconds() {
        #expect(WatcherVisibility.thirtyMinutes.seconds == 1800)
        #expect(WatcherVisibility.sevenDays.seconds == 604_800)
        // Capped at 7 days on purpose (no unbounded "always" option).
        #expect(WatcherVisibility.allCases.map(\.rawValue).max() == 604_800)
        #expect(WatcherVisibility.allCases.count == 5)
    }
}

@Suite("SessionStore watcher settings delegation")
@MainActor
struct SessionStoreWatcherSettingsTests {

    @Test("setScanInterval is forwarded to the monitor service")
    func forwardsScanInterval() {
        let mock = MockSessionMonitorService()
        let store = SessionStore(monitorService: mock)
        store.setScanInterval(5)
        #expect(mock.lastScanInterval == 5)
    }

    @Test("setVisibility is forwarded to the monitor service")
    func forwardsVisibility() {
        let mock = MockSessionMonitorService()
        let store = SessionStore(monitorService: mock)
        store.setVisibility(7200)
        #expect(mock.lastVisibility == 7200)
    }
}

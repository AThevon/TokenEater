import SwiftUI
import UserNotifications

@MainActor
@Observable
final class SettingsStore {
    // Menu bar
    var showMenuBar: Bool {
        didSet { UserDefaults.standard.set(showMenuBar, forKey: "showMenuBar") }
    }
    var pinnedMetrics: Set<MetricID> {
        didSet { savePinnedMetrics() }
    }
    var pacingDisplayMode: PacingDisplayMode {
        didSet { UserDefaults.standard.set(pacingDisplayMode.rawValue, forKey: "pacingDisplayMode") }
    }
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    // Proxy
    var proxyEnabled: Bool {
        didSet { UserDefaults.standard.set(proxyEnabled, forKey: "proxyEnabled") }
    }
    var proxyHost: String {
        didSet { UserDefaults.standard.set(proxyHost, forKey: "proxyHost") }
    }
    var proxyPort: Int {
        didSet { UserDefaults.standard.set(proxyPort, forKey: "proxyPort") }
    }

    var proxyConfig: ProxyConfig {
        ProxyConfig(enabled: proxyEnabled, host: proxyHost, port: proxyPort)
    }

    // Notifications
    var notificationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationService: NotificationServiceProtocol
    private let keychainService: KeychainServiceProtocol

    init(
        notificationService: NotificationServiceProtocol = NotificationService(),
        keychainService: KeychainServiceProtocol = KeychainService()
    ) {
        self.notificationService = notificationService
        self.keychainService = keychainService

        self.showMenuBar = UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.proxyEnabled = UserDefaults.standard.bool(forKey: "proxyEnabled")
        self.proxyHost = UserDefaults.standard.string(forKey: "proxyHost") ?? "127.0.0.1"
        self.proxyPort = {
            let port = UserDefaults.standard.integer(forKey: "proxyPort")
            return port > 0 ? port : 1080
        }()
        self.pacingDisplayMode = PacingDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "pacingDisplayMode") ?? "dotDelta"
        ) ?? .dotDelta

        if let saved = UserDefaults.standard.stringArray(forKey: "pinnedMetrics") {
            self.pinnedMetrics = Set(saved.compactMap { MetricID(rawValue: $0) })
        } else {
            self.pinnedMetrics = [.fiveHour, .sevenDay]
        }
    }

    // MARK: - Metrics

    func toggleMetric(_ metric: MetricID) {
        if pinnedMetrics.contains(metric) {
            if pinnedMetrics.count > 1 {
                pinnedMetrics.remove(metric)
            }
        } else {
            pinnedMetrics.insert(metric)
        }
    }

    private func savePinnedMetrics() {
        UserDefaults.standard.set(pinnedMetrics.map(\.rawValue), forKey: "pinnedMetrics")
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        notificationService.requestPermission()
    }

    func sendTestNotification() {
        notificationService.sendTest()
    }

    func refreshNotificationStatus() async {
        notificationStatus = await notificationService.checkAuthorizationStatus()
    }

    // MARK: - Keychain

    func keychainTokenExists() -> Bool {
        keychainService.tokenExists()
    }

    func readKeychainToken() -> String? {
        keychainService.readOAuthToken()
    }
}

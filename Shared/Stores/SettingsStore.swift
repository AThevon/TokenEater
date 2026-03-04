import SwiftUI
import UserNotifications

@MainActor
final class SettingsStore: ObservableObject {
    // Menu bar
    @Published var showMenuBar: Bool {
        didSet { UserDefaults.standard.set(showMenuBar, forKey: "showMenuBar") }
    }
    @Published var pinnedMetrics: Set<MetricID> {
        didSet { savePinnedMetrics() }
    }
    @Published var pacingDisplayMode: PacingDisplayMode {
        didSet { UserDefaults.standard.set(pacingDisplayMode.rawValue, forKey: "pacingDisplayMode") }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    // Proxy
    @Published var proxyEnabled: Bool {
        didSet { UserDefaults.standard.set(proxyEnabled, forKey: "proxyEnabled") }
    }
    @Published var proxyHost: String {
        didSet { UserDefaults.standard.set(proxyHost, forKey: "proxyHost") }
    }
    @Published var proxyPort: Int {
        didSet { UserDefaults.standard.set(proxyPort, forKey: "proxyPort") }
    }

    // Overlay
    @Published var overlayEnabled: Bool {
        didSet { UserDefaults.standard.set(overlayEnabled, forKey: "overlayEnabled") }
    }
    @Published var overlayDockEffect: Bool {
        didSet { UserDefaults.standard.set(overlayDockEffect, forKey: "overlayDockEffect") }
    }
    @Published var overlayScale: Double {
        didSet { UserDefaults.standard.set(overlayScale, forKey: "overlayScale") }
    }
    @Published var overlayLeftSide: Bool {
        didSet { UserDefaults.standard.set(overlayLeftSide, forKey: "overlayLeftSide") }
    }
    @Published var watchersDetailedMode: Bool {
        didSet { UserDefaults.standard.set(watchersDetailedMode, forKey: "watchersDetailedMode") }
    }

    // Performance
    @Published var particlesEnabled: Bool {
        didSet { UserDefaults.standard.set(particlesEnabled, forKey: "particlesEnabled") }
    }
    @Published var animatedGradientEnabled: Bool {
        didSet { UserDefaults.standard.set(animatedGradientEnabled, forKey: "animatedGradientEnabled") }
    }
    @Published var watcherAnimationsEnabled: Bool {
        didSet { UserDefaults.standard.set(watcherAnimationsEnabled, forKey: "watcherAnimationsEnabled") }
    }
    @Published var sessionMonitorEnabled: Bool {
        didSet { UserDefaults.standard.set(sessionMonitorEnabled, forKey: "sessionMonitorEnabled") }
    }

    // Pacing
    @Published var pacingMargin: Int {
        didSet { UserDefaults.standard.set(pacingMargin, forKey: "pacingMargin") }
    }

    var proxyConfig: ProxyConfig {
        ProxyConfig(enabled: proxyEnabled, host: proxyHost, port: proxyPort)
    }

    // MARK: - Metric toggles

    var showFiveHour: Bool {
        get { pinnedMetrics.contains(.fiveHour) }
        set {
            if newValue { pinnedMetrics.insert(.fiveHour) }
            else if pinnedMetrics.count > 1 { pinnedMetrics.remove(.fiveHour) }
        }
    }

    var showSevenDay: Bool {
        get { pinnedMetrics.contains(.sevenDay) }
        set {
            if newValue { pinnedMetrics.insert(.sevenDay) }
            else if pinnedMetrics.count > 1 { pinnedMetrics.remove(.sevenDay) }
        }
    }

    var showSonnet: Bool {
        get { pinnedMetrics.contains(.sonnet) }
        set {
            if newValue { pinnedMetrics.insert(.sonnet) }
            else if pinnedMetrics.count > 1 { pinnedMetrics.remove(.sonnet) }
        }
    }

    var showPacing: Bool {
        get { pinnedMetrics.contains(.pacing) }
        set {
            if newValue { pinnedMetrics.insert(.pacing) }
            else if pinnedMetrics.count > 1 { pinnedMetrics.remove(.pacing) }
        }
    }

    // Notifications
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined

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
        self.overlayEnabled = UserDefaults.standard.object(forKey: "overlayEnabled") as? Bool ?? true
        self.overlayDockEffect = UserDefaults.standard.object(forKey: "overlayDockEffect") as? Bool ?? true
        self.overlayScale = UserDefaults.standard.object(forKey: "overlayScale") as? Double ?? 1.0
        self.overlayLeftSide = UserDefaults.standard.bool(forKey: "overlayLeftSide")
        self.watchersDetailedMode = UserDefaults.standard.object(forKey: "watchersDetailedMode") as? Bool ?? true
        self.particlesEnabled = UserDefaults.standard.object(forKey: "particlesEnabled") as? Bool ?? true
        self.animatedGradientEnabled = UserDefaults.standard.object(forKey: "animatedGradientEnabled") as? Bool ?? true
        self.watcherAnimationsEnabled = UserDefaults.standard.object(forKey: "watcherAnimationsEnabled") as? Bool ?? true
        self.sessionMonitorEnabled = UserDefaults.standard.object(forKey: "sessionMonitorEnabled") as? Bool ?? true
        self.pacingMargin = {
            let val = UserDefaults.standard.integer(forKey: "pacingMargin")
            return val > 0 ? val : 10
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
        let newStatus = await notificationService.checkAuthorizationStatus()
        if newStatus != notificationStatus {
            notificationStatus = newStatus
        }
    }

    // MARK: - Keychain

    func keychainTokenExists() -> Bool {
        keychainService.tokenExists()
    }

    func readKeychainToken() -> String? {
        keychainService.readOAuthToken()
    }
}

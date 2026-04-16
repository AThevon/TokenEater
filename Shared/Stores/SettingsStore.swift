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
    @Published var resetDisplayFormat: ResetDisplayFormat {
        didSet { UserDefaults.standard.set(resetDisplayFormat.rawValue, forKey: "resetDisplayFormat") }
    }
    /// When true, the reset countdown text is coloured based on a risk score
    /// (utilization x remaining minutes) rather than the static user-picked
    /// hex. Useful to signal urgency without constantly watching the number.
    @Published var smartResetColor: Bool {
        didSet { UserDefaults.standard.set(smartResetColor, forKey: "smartResetColor") }
    }
    @Published var sessionPacingDisplayMode: PacingDisplayMode {
        didSet { UserDefaults.standard.set(sessionPacingDisplayMode.rawValue, forKey: "sessionPacingDisplayMode") }
    }
    @Published var weeklyPacingDisplayMode: PacingDisplayMode {
        didSet { UserDefaults.standard.set(weeklyPacingDisplayMode.rawValue, forKey: "weeklyPacingDisplayMode") }
    }
    /// Hex string ("#RRGGBB") for the menu-bar reset countdown text.
    /// Empty = use the system's primary label color.
    @Published var resetTextColorHex: String {
        didSet { UserDefaults.standard.set(resetTextColorHex, forKey: "resetTextColorHex") }
    }
    /// Hex string ("#RRGGBB") for the "5h" / "7d" / "S" period label.
    /// Empty = use the system's tertiary label color.
    @Published var sessionPeriodColorHex: String {
        didSet { UserDefaults.standard.set(sessionPeriodColorHex, forKey: "sessionPeriodColorHex") }
    }
    @Published var displaySonnet: Bool {
        didSet {
            UserDefaults.standard.set(displaySonnet, forKey: "displaySonnet")
            if !displaySonnet {
                // Drop any sonnet-related pins so the menu bar does not keep
                // a stale reference to a hidden metric.
                pinnedMetrics.remove(.sonnet)
            }
        }
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
    @Published var watcherStyle: WatcherStyle {
        didSet { UserDefaults.standard.set(watcherStyle.rawValue, forKey: "watcherStyle") }
    }
    @Published var watcherDisplayMode: WatcherDisplayMode {
        didSet { UserDefaults.standard.set(watcherDisplayMode.rawValue, forKey: "watcherDisplayMode") }
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

    // Refresh interval (seconds) — minimum 180 (3min), default 300 (5min)
    @Published var refreshInterval: Int {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
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

    var showSessionPacing: Bool {
        get { pinnedMetrics.contains(.sessionPacing) }
        set {
            if newValue { pinnedMetrics.insert(.sessionPacing) }
            else if pinnedMetrics.count > 1 { pinnedMetrics.remove(.sessionPacing) }
        }
    }

    var showWeeklyPacing: Bool {
        get { pinnedMetrics.contains(.weeklyPacing) }
        set {
            if newValue { pinnedMetrics.insert(.weeklyPacing) }
            else if pinnedMetrics.count > 1 { pinnedMetrics.remove(.weeklyPacing) }
        }
    }

    // Notifications
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined

    // Keychain helper
    @Published var helperStatus: HelperStatus = .notInstalled
    @Published var helperBusy: Bool = false
    @Published var helperLastError: String?
    @Published var helperSyncInterval: Int {
        didSet { UserDefaults.standard.set(helperSyncInterval, forKey: "helperSyncInterval") }
    }

    private let notificationService: NotificationServiceProtocol
    private let tokenProvider: TokenProviderProtocol
    private let helperManager: HelperManagerProtocol

    init(
        notificationService: NotificationServiceProtocol = NotificationService(),
        tokenProvider: TokenProviderProtocol = TokenProvider(),
        helperManager: HelperManagerProtocol = HelperManagerService()
    ) {
        self.notificationService = notificationService
        self.tokenProvider = tokenProvider
        self.helperManager = helperManager

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
        self.overlayScale = UserDefaults.standard.object(forKey: "overlayScale") as? Double ?? 1.1
        self.overlayLeftSide = UserDefaults.standard.bool(forKey: "overlayLeftSide")
        self.watchersDetailedMode = UserDefaults.standard.object(forKey: "watchersDetailedMode") as? Bool ?? true
        self.watcherStyle = WatcherStyle(
            rawValue: UserDefaults.standard.string(forKey: "watcherStyle") ?? "frost"
        ) ?? .frost
        self.watcherDisplayMode = WatcherDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "watcherDisplayMode") ?? "branchPriority"
        ) ?? .branchPriority
        self.particlesEnabled = UserDefaults.standard.object(forKey: "particlesEnabled") as? Bool ?? true
        self.animatedGradientEnabled = UserDefaults.standard.object(forKey: "animatedGradientEnabled") as? Bool ?? true
        self.watcherAnimationsEnabled = UserDefaults.standard.object(forKey: "watcherAnimationsEnabled") as? Bool ?? true
        self.sessionMonitorEnabled = UserDefaults.standard.object(forKey: "sessionMonitorEnabled") as? Bool ?? true
        self.pacingMargin = {
            let val = UserDefaults.standard.integer(forKey: "pacingMargin")
            return val > 0 ? val : 10
        }()
        self.refreshInterval = {
            let val = UserDefaults.standard.integer(forKey: "refreshInterval")
            return val >= 180 ? val : 300
        }()
        self.resetDisplayFormat = ResetDisplayFormat(
            rawValue: UserDefaults.standard.string(forKey: "resetDisplayFormat") ?? "relative"
        ) ?? .relative
        self.resetTextColorHex = UserDefaults.standard.string(forKey: "resetTextColorHex") ?? ""
        self.sessionPeriodColorHex = UserDefaults.standard.string(forKey: "sessionPeriodColorHex") ?? ""
        self.smartResetColor = UserDefaults.standard.bool(forKey: "smartResetColor")

        // Migrate the legacy global `pacingDisplayMode` into the two per-bucket
        // settings so existing users keep the mode they had. If either per-bucket
        // value has been saved before, prefer it.
        let legacyMode = PacingDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "pacingDisplayMode") ?? "dotDelta"
        ) ?? .dotDelta
        self.sessionPacingDisplayMode = PacingDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "sessionPacingDisplayMode") ?? legacyMode.rawValue
        ) ?? legacyMode
        self.weeklyPacingDisplayMode = PacingDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "weeklyPacingDisplayMode") ?? legacyMode.rawValue
        ) ?? legacyMode
        self.helperSyncInterval = {
            let raw = UserDefaults.standard.integer(forKey: "helperSyncInterval")
            return raw >= 30 ? raw : Int(HelperManagerService.defaultSyncInterval)
        }()
        self.helperStatus = helperManager.currentStatus()
        var legacyPinned: Set<MetricID>
        if let saved = UserDefaults.standard.stringArray(forKey: "pinnedMetrics") {
            // Migrate legacy "pacing" (covered weekly only) to the explicit weeklyPacing id.
            let normalized = saved.map { $0 == "pacing" ? "weeklyPacing" : $0 }
            legacyPinned = Set(normalized.compactMap { MetricID(rawValue: $0) })
        } else {
            legacyPinned = [.fiveHour, .sevenDay]
        }

        // Migrate the old `showSessionReset` boolean into the new `.sessionReset`
        // pinnable metric so existing users keep seeing the countdown they opted
        // in to. The boolean itself is removed below.
        if UserDefaults.standard.object(forKey: "showSessionReset") != nil,
           UserDefaults.standard.bool(forKey: "showSessionReset") {
            legacyPinned.insert(.sessionReset)
        }
        self.pinnedMetrics = legacyPinned

        // displaySonnet defaults to false for new installs. Legacy users who
        // had .sonnet pinned keep it on by default so their setup does not
        // silently lose the ring after upgrade.
        if UserDefaults.standard.object(forKey: "displaySonnet") != nil {
            self.displaySonnet = UserDefaults.standard.bool(forKey: "displaySonnet")
        } else {
            self.displaySonnet = legacyPinned.contains(.sonnet)
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

    // MARK: - Credentials

    func credentialsTokenExists() -> Bool {
        tokenProvider.currentToken() != nil
    }

    // MARK: - Keychain helper

    func refreshHelperStatus() {
        helperStatus = helperManager.currentStatus()
    }

    func installHelper() async {
        helperBusy = true
        helperLastError = nil
        defer {
            helperBusy = false
            refreshHelperStatus()
        }
        do {
            try helperManager.install(syncInterval: TimeInterval(helperSyncInterval))
            tokenProvider.invalidateToken()
        } catch {
            helperLastError = error.localizedDescription
        }
    }

    func uninstallHelper() async {
        helperBusy = true
        helperLastError = nil
        defer {
            helperBusy = false
            refreshHelperStatus()
        }
        do {
            try helperManager.uninstall()
            tokenProvider.invalidateToken()
        } catch {
            helperLastError = error.localizedDescription
        }
    }

    func forceHelperSync() async {
        helperBusy = true
        helperLastError = nil
        defer {
            helperBusy = false
            refreshHelperStatus()
        }
        do {
            try helperManager.forceSync()
        } catch {
            helperLastError = error.localizedDescription
        }
    }
}

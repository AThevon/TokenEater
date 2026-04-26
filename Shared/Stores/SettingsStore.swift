import SwiftUI
import UserNotifications
import ServiceManagement

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
    /// Global "Smart Color" theming. When ON, color codes throughout the app
    /// (gauges, reset countdowns) integrate the time-to-reset factor instead of
    /// raw thresholds. Example: 95% utilization with 2 minutes left to reset
    /// stays green rather than going red. Falls back to threshold-based coloring
    /// when no reset date is available.
    @Published var smartColorEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smartColorEnabled, forKey: "smartColorEnabled")
            sharedFileService.updateSmartColorEnabled(smartColorEnabled)
        }
    }
    /// User-selected temperament for the smart color algorithm. Shifts
    /// when the gauge transitions from chill -> warning -> hot. See
    /// `SmartColorProfile` for the parameter mapping.
    @Published var smartColorProfile: SmartColorProfile {
        didSet { UserDefaults.standard.set(smartColorProfile.rawValue, forKey: "smartColorProfile") }
    }
    /// Typography / separator style for the pinned metrics in the menu bar.
    @Published var menuBarStyle: MenuBarStyle {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
    }
    /// Glyph used for the pacing indicator across menu bar + popover.
    @Published var pacingShape: PacingShape {
        didSet { UserDefaults.standard.set(pacingShape.rawValue, forKey: "pacingShape") }
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
    /// Controls whether the Sonnet satellite appears in the popover Classic
    /// variant AND in the dashboard constellation. The menu-bar visibility of
    /// Sonnet is driven by `pinnedMetrics.contains(.sonnet)`, independently.
    @Published var displaySonnet: Bool {
        didSet { UserDefaults.standard.set(displaySonnet, forKey: "displaySonnet") }
    }
    /// Same as `displaySonnet` but for Claude Design.
    @Published var displayDesign: Bool {
        didSet { UserDefaults.standard.set(displayDesign, forKey: "displayDesign") }
    }

    // MARK: - Popover
    /// Full layout configuration for the menu-bar popover. 3 variants share this
    /// struct; switching `activeVariant` leaves the other variants untouched so
    /// the user can keep 3 distinct preferences. Persisted as JSON under
    /// `popoverConfig` in UserDefaults.
    @Published var popoverConfig: PopoverConfig {
        didSet { savePopoverConfig() }
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
    @Published var overlayTriggerZone: OverlayTriggerZone {
        didSet { UserDefaults.standard.set(overlayTriggerZone.rawValue, forKey: "overlayTriggerZone") }
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
    @Published var watcherAnimationsEnabled: Bool {
        didSet { UserDefaults.standard.set(watcherAnimationsEnabled, forKey: "watcherAnimationsEnabled") }
    }

    // Pacing
    @Published var pacingMargin: Int {
        didSet { UserDefaults.standard.set(pacingMargin, forKey: "pacingMargin") }
    }

    // Notifications - master switch and per-event toggles.
    // When `notificationsEnabled` is false, NotificationService.evaluate
    // bails out before touching the per-event toggles. The user keeps their
    // granular config while silencing the whole pipeline.
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    @Published var notifTrackFiveHour: Bool {
        didSet { UserDefaults.standard.set(notifTrackFiveHour, forKey: "notifTrackFiveHour") }
    }
    @Published var notifTrackWeekly: Bool {
        didSet { UserDefaults.standard.set(notifTrackWeekly, forKey: "notifTrackWeekly") }
    }
    @Published var notifTrackSonnet: Bool {
        didSet { UserDefaults.standard.set(notifTrackSonnet, forKey: "notifTrackSonnet") }
    }
    @Published var notifTrackDesign: Bool {
        didSet { UserDefaults.standard.set(notifTrackDesign, forKey: "notifTrackDesign") }
    }
    /// When false, only escalations (orange / red) fire. Recovery to green stays silent.
    @Published var notifSendRecovery: Bool {
        didSet { UserDefaults.standard.set(notifSendRecovery, forKey: "notifSendRecovery") }
    }
    /// Pacing zone transitions
    @Published var notifPacingHot: Bool {
        didSet { UserDefaults.standard.set(notifPacingHot, forKey: "notifPacingHot") }
    }
    @Published var notifPacingWarning: Bool {
        didSet { UserDefaults.standard.set(notifPacingWarning, forKey: "notifPacingWarning") }
    }
    /// Scheduled reminders (15min before 5h reset, 1h before weekly reset)
    @Published var notifResetReminderSession: Bool {
        didSet { UserDefaults.standard.set(notifResetReminderSession, forKey: "notifResetReminderSession") }
    }
    @Published var notifResetReminderWeekly: Bool {
        didSet { UserDefaults.standard.set(notifResetReminderWeekly, forKey: "notifResetReminderWeekly") }
    }
    /// Paid extra credits pool transitions
    @Published var notifExtraCredits: Bool {
        didSet { UserDefaults.standard.set(notifExtraCredits, forKey: "notifExtraCredits") }
    }
    /// Token expired / authentication issues
    @Published var notifTokenExpired: Bool {
        didSet { UserDefaults.standard.set(notifTokenExpired, forKey: "notifTokenExpired") }
    }

    // Refresh interval (seconds) - minimum 180 (3min), default 300 (5min)
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

    // Launch at Login - toggle + reflect actual SMAppService.mainApp status
    @Published var launchAtLoginEnabled: Bool {
        didSet {
            guard launchAtLoginEnabled != oldValue else { return }
            UserDefaults.standard.set(launchAtLoginEnabled, forKey: "launchAtLoginEnabled")
            applyLaunchAtLogin(launchAtLoginEnabled)
        }
    }

    private let notificationService: NotificationServiceProtocol
    private let tokenProvider: TokenProviderProtocol
    private let sharedFileService: SharedFileServiceProtocol

    init(
        notificationService: NotificationServiceProtocol = NotificationService(),
        tokenProvider: TokenProviderProtocol = TokenProvider(),
        sharedFileService: SharedFileServiceProtocol = SharedFileService()
    ) {
        self.notificationService = notificationService
        self.tokenProvider = tokenProvider
        self.sharedFileService = sharedFileService

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
        self.overlayTriggerZone = OverlayTriggerZone(
            rawValue: UserDefaults.standard.string(forKey: "overlayTriggerZone") ?? "medium"
        ) ?? .medium
        self.watchersDetailedMode = UserDefaults.standard.object(forKey: "watchersDetailedMode") as? Bool ?? true
        self.watcherStyle = WatcherStyle(
            rawValue: UserDefaults.standard.string(forKey: "watcherStyle") ?? "frost"
        ) ?? .frost
        self.watcherDisplayMode = WatcherDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "watcherDisplayMode") ?? "branchPriority"
        ) ?? .branchPriority
        self.watcherAnimationsEnabled = UserDefaults.standard.object(forKey: "watcherAnimationsEnabled") as? Bool ?? true
        // Reconcile the stored toggle with the actual SMAppService state - user
        // might have flipped it from System Settings without going through the
        // app, and we must not diverge from macOS's view of the world.
        let storedLaunchAtLogin = UserDefaults.standard.object(forKey: "launchAtLoginEnabled") as? Bool ?? false
        let systemLaunchAtLogin = SMAppService.mainApp.status == .enabled
        self.launchAtLoginEnabled = systemLaunchAtLogin || storedLaunchAtLogin
        if storedLaunchAtLogin != systemLaunchAtLogin {
            // Persist the reconciled value without re-triggering the didSet
            // (we only want to register/unregister when the user flips the
            // toggle; the init path just mirrors the OS state).
            UserDefaults.standard.set(systemLaunchAtLogin, forKey: "launchAtLoginEnabled")
        }
        self.pacingMargin = {
            let val = UserDefaults.standard.integer(forKey: "pacingMargin")
            let raw = val > 0 ? val : 10
            let snapped = (Int((Double(raw) / 5.0).rounded()) * 5)
            return min(30, max(5, snapped))
        }()
        self.refreshInterval = {
            let val = UserDefaults.standard.integer(forKey: "refreshInterval")
            return val >= 180 ? val : 300
        }()

        // Notification toggles
        // First-launch defaults (no key in UserDefaults yet) follow the user-validated
        // policy : master ON, 5h / 7d / Design ON, Sonnet OFF, recovery ON, hot ON,
        // warning OFF, reset reminders OFF, extra credits ON, token expired OFF.
        self.notificationsEnabled = Self.boolDefault(key: "notificationsEnabled", default: true)
        self.notifTrackFiveHour = Self.boolDefault(key: "notifTrackFiveHour", default: true)
        self.notifTrackWeekly = Self.boolDefault(key: "notifTrackWeekly", default: true)
        self.notifTrackSonnet = Self.boolDefault(key: "notifTrackSonnet", default: false)
        self.notifTrackDesign = Self.boolDefault(key: "notifTrackDesign", default: true)
        self.notifSendRecovery = Self.boolDefault(key: "notifSendRecovery", default: true)
        self.notifPacingHot = Self.boolDefault(key: "notifPacingHot", default: true)
        self.notifPacingWarning = Self.boolDefault(key: "notifPacingWarning", default: false)
        self.notifResetReminderSession = Self.boolDefault(key: "notifResetReminderSession", default: false)
        self.notifResetReminderWeekly = Self.boolDefault(key: "notifResetReminderWeekly", default: false)
        self.notifExtraCredits = Self.boolDefault(key: "notifExtraCredits", default: true)
        self.notifTokenExpired = Self.boolDefault(key: "notifTokenExpired", default: false)
        self.resetDisplayFormat = ResetDisplayFormat(
            rawValue: UserDefaults.standard.string(forKey: "resetDisplayFormat") ?? "relative"
        ) ?? .relative
        self.resetTextColorHex = UserDefaults.standard.string(forKey: "resetTextColorHex") ?? ""
        self.sessionPeriodColorHex = UserDefaults.standard.string(forKey: "sessionPeriodColorHex") ?? ""
        // Default ON. Migration: if the user had explicitly set the legacy
        // "smartResetColor" key, respect that decision; otherwise opt them into
        // smart coloring globally.
        let initialSmartColor: Bool = {
            if let v = UserDefaults.standard.object(forKey: "smartColorEnabled") as? Bool { return v }
            if let legacy = UserDefaults.standard.object(forKey: "smartResetColor") as? Bool { return legacy }
            return true
        }()
        self.smartColorEnabled = initialSmartColor
        // Push the resolved value to the shared file so the (sandboxed) widget
        // sees the same setting on first launch without waiting for a toggle.
        sharedFileService.updateSmartColorEnabled(initialSmartColor)
        self.smartColorProfile = SmartColorProfile(
            rawValue: UserDefaults.standard.string(forKey: "smartColorProfile") ?? SmartColorProfile.default.rawValue
        ) ?? .default
        self.menuBarStyle = MenuBarStyle(
            rawValue: UserDefaults.standard.string(forKey: "menuBarStyle") ?? "classic"
        ) ?? .classic
        self.pacingShape = PacingShape(
            rawValue: UserDefaults.standard.string(forKey: "pacingShape") ?? "circle"
        ) ?? .circle

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

        // displaySonnet and displayDesign default to false for everyone -
        // the satellites are opt-in. Users who had the old behaviour (sonnet
        // pinned automatically toggled displaySonnet to true) keep whatever
        // they had saved.
        if UserDefaults.standard.object(forKey: "displaySonnet") != nil {
            self.displaySonnet = UserDefaults.standard.bool(forKey: "displaySonnet")
        } else {
            self.displaySonnet = false
        }
        self.displayDesign = UserDefaults.standard.object(forKey: "displayDesign") != nil
            ? UserDefaults.standard.bool(forKey: "displayDesign")
            : false

        // Popover layout config. Fresh install or decode failure -> defaults
        // that reproduce the v4.10.x popover visually (Classic variant, all
        // blocks visible).
        if let data = UserDefaults.standard.data(forKey: "popoverConfig"),
           let decoded = try? JSONDecoder().decode(PopoverConfig.self, from: data) {
            self.popoverConfig = Self.reconcile(decoded)
        } else {
            self.popoverConfig = .default
        }
    }

    // MARK: - Popover persistence

    private func savePopoverConfig() {
        guard let data = try? JSONEncoder().encode(popoverConfig) else { return }
        UserDefaults.standard.set(data, forKey: "popoverConfig")
    }

    /// Reads a Bool from UserDefaults but distinguishes "absent" from "false".
    /// `UserDefaults.bool(forKey:)` returns false for missing keys, which would
    /// silently override our intended default. Using `object(forKey:)` lets us
    /// fall back only when the key has never been written.
    private static func boolDefault(key: String, default fallback: Bool) -> Bool {
        if let stored = UserDefaults.standard.object(forKey: key) as? Bool {
            return stored
        }
        return fallback
    }

    /// Ensures a decoded config still satisfies the validation rules (at least
    /// one visible block in hero+middle for non-focus variants). If anything is
    /// off, fall back to defaults for that variant only.
    private static func reconcile(_ config: PopoverConfig) -> PopoverConfig {
        var fixed = config
        if !fixed.hasVisibleContent(for: .classic) { fixed.classic = .classicDefault }
        if !fixed.hasVisibleContent(for: .compact) { fixed.compact = .compactDefault }
        // Focus always valid by construction (hero driven by focusHero radio).
        return fixed
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

    // MARK: - Launch at Login

    private func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            // Revert the published state if the OS refused the call (usually
            // because the user denied it in Background Items prefs). Avoids a
            // UI that claims the toggle is on while launchd disagrees.
            DispatchQueue.main.async {
                let actual = SMAppService.mainApp.status == .enabled
                if self.launchAtLoginEnabled != actual {
                    self.launchAtLoginEnabled = actual
                }
            }
        }
    }

}

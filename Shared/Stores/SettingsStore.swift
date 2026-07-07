import SwiftUI
import UserNotifications
import ServiceManagement
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    // Display / menu bar - extracted into a child ObservableObject domain slice,
    // same pattern as `pacing`. Views should prefer `settings.display.$x` for
    // bindings; the forwards below keep existing non-binding call sites
    // compiling without change.
    @Published var display: DisplaySettingsStore
    private var displayRelay: AnyCancellable?

    // Backwards-compatible forwards (no $ bindings should target these).
    var showMenuBar: Bool {
        get { display.showMenuBar } set { display.showMenuBar = newValue }
    }
    var launchInBackground: Bool {
        get { display.launchInBackground } set { display.launchInBackground = newValue }
    }
    var pinnedMetrics: Set<MetricID> {
        get { display.pinnedMetrics } set { display.pinnedMetrics = newValue }
    }
    var resetDisplayFormat: ResetDisplayFormat {
        get { display.resetDisplayFormat } set { display.resetDisplayFormat = newValue }
    }
    var smartColorEnabled: Bool {
        get { display.smartColorEnabled } set { display.smartColorEnabled = newValue }
    }
    var smartColorProfile: SmartColorProfile {
        get { display.smartColorProfile } set { display.smartColorProfile = newValue }
    }
    var glowIntensity: DS.GlowIntensity {
        get { display.glowIntensity } set { display.glowIntensity = newValue }
    }
    var menuBarStyle: MenuBarStyle {
        get { display.menuBarStyle } set { display.menuBarStyle = newValue }
    }
    var pacingShape: PacingShape {
        get { display.pacingShape } set { display.pacingShape = newValue }
    }
    var sessionPacingDisplayMode: PacingDisplayMode {
        get { display.sessionPacingDisplayMode } set { display.sessionPacingDisplayMode = newValue }
    }
    var weeklyPacingDisplayMode: PacingDisplayMode {
        get { display.weeklyPacingDisplayMode } set { display.weeklyPacingDisplayMode = newValue }
    }
    var resetTextColorHex: String {
        get { display.resetTextColorHex } set { display.resetTextColorHex = newValue }
    }
    var sessionPeriodColorHex: String {
        get { display.sessionPeriodColorHex } set { display.sessionPeriodColorHex = newValue }
    }
    var displaySonnet: Bool {
        get { display.displaySonnet } set { display.displaySonnet = newValue }
    }
    var displayDesign: Bool {
        get { display.displayDesign } set { display.displayDesign = newValue }
    }
    var displayFable: Bool {
        get { display.displayFable } set { display.displayFable = newValue }
    }
    /// Same as `displayDesign` but for the paid Extra Credits pool. Only
    /// surfaced in settings when `UsageStore.hasExtraCredits` is true.
    var displayExtraCredits: Bool {
        get { display.displayExtraCredits } set { display.displayExtraCredits = newValue }
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

    // Overlay + Performance - extracted into a child ObservableObject domain
    // slice, same pattern as `pacing`. Views should prefer `settings.overlay.$x`
    // for bindings; the forwards below keep existing non-binding call sites
    // compiling without change.
    @Published var overlay: OverlaySettingsStore
    private var overlayRelay: AnyCancellable?

    // Backwards-compatible forwards (no $ bindings should target these).
    var overlayEnabled: Bool {
        get { overlay.overlayEnabled } set { overlay.overlayEnabled = newValue }
    }
    var overlayDockEffect: Bool {
        get { overlay.overlayDockEffect } set { overlay.overlayDockEffect = newValue }
    }
    var overlayScale: Double {
        get { overlay.overlayScale } set { overlay.overlayScale = newValue }
    }
    var overlayLeftSide: Bool {
        get { overlay.overlayLeftSide } set { overlay.overlayLeftSide = newValue }
    }
    var overlayTriggerZone: OverlayTriggerZone {
        get { overlay.overlayTriggerZone } set { overlay.overlayTriggerZone = newValue }
    }
    var watchersDetailedMode: Bool {
        get { overlay.watchersDetailedMode } set { overlay.watchersDetailedMode = newValue }
    }
    var watcherStyle: WatcherStyle {
        get { overlay.watcherStyle } set { overlay.watcherStyle = newValue }
    }
    var watcherDisplayMode: WatcherDisplayMode {
        get { overlay.watcherDisplayMode } set { overlay.watcherDisplayMode = newValue }
    }
    var watcherScanInterval: WatcherScanInterval {
        get { overlay.watcherScanInterval } set { overlay.watcherScanInterval = newValue }
    }
    var watcherVisibility: WatcherVisibility {
        get { overlay.watcherVisibility } set { overlay.watcherVisibility = newValue }
    }
    var watcherAnimationsEnabled: Bool {
        get { overlay.watcherAnimationsEnabled } set { overlay.watcherAnimationsEnabled = newValue }
    }

    // Pacing - extracted into a child ObservableObject domain slice. Views should
    // prefer `settings.pacing.$x` for bindings; the forwards below keep existing
    // non-binding call sites compiling without change.
    @Published var pacing: PacingSettingsStore
    private var pacingRelay: AnyCancellable?

    // Backwards-compatible forwards (no $ bindings should target these).
    var pacingMargin: Int {
        get { pacing.margin } set { pacing.margin = newValue }
    }
    var pacingWorkweekEnabled: Bool {
        get { pacing.workweekEnabled } set { pacing.workweekEnabled = newValue }
    }
    var pacingActiveDays: Set<Int> {
        get { pacing.activeDays } set { pacing.activeDays = newValue }
    }
    var pacingHoursEnabled: Bool {
        get { pacing.hoursEnabled } set { pacing.hoursEnabled = newValue }
    }
    var pacingStartHour: Int {
        get { pacing.startHour } set { pacing.startHour = newValue }
    }
    var pacingEndHour: Int {
        get { pacing.endHour } set { pacing.endHour = newValue }
    }
    /// The resolved schedule handed to the pacing calculator + widget.
    var pacingSchedule: PacingSchedule { pacing.schedule }

    // Notifications - extracted into a child ObservableObject domain slice, same
    // pattern as `pacing`. Views should prefer `settings.notification.$x` for
    // bindings; the forwards below keep existing non-binding call sites
    // compiling without change.
    @Published var notification: NotificationSettingsStore
    private var notificationRelay: AnyCancellable?

    // Backwards-compatible forwards (no $ bindings should target these).
    var notificationsEnabled: Bool {
        get { notification.enabled } set { notification.enabled = newValue }
    }
    var notifTrackFiveHour: Bool {
        get { notification.trackFiveHour } set { notification.trackFiveHour = newValue }
    }
    var notifTrackWeekly: Bool {
        get { notification.trackWeekly } set { notification.trackWeekly = newValue }
    }
    var notifTrackSonnet: Bool {
        get { notification.trackSonnet } set { notification.trackSonnet = newValue }
    }
    var notifTrackDesign: Bool {
        get { notification.trackDesign } set { notification.trackDesign = newValue }
    }
    var notifTrackFable: Bool {
        get { notification.trackFable } set { notification.trackFable = newValue }
    }
    var notifSendRecovery: Bool {
        get { notification.sendRecovery } set { notification.sendRecovery = newValue }
    }
    var notifPacingHot: Bool {
        get { notification.pacingHot } set { notification.pacingHot = newValue }
    }
    var notifPacingWarning: Bool {
        get { notification.pacingWarning } set { notification.pacingWarning = newValue }
    }
    var notifResetReminderSession: Bool {
        get { notification.resetReminderSession } set { notification.resetReminderSession = newValue }
    }
    var notifResetReminderWeekly: Bool {
        get { notification.resetReminderWeekly } set { notification.resetReminderWeekly = newValue }
    }
    var notifResetReminderSessionOffset: Int {
        get { notification.resetReminderSessionOffset } set { notification.resetReminderSessionOffset = newValue }
    }
    var notifResetReminderWeeklyOffset: Int {
        get { notification.resetReminderWeeklyOffset } set { notification.resetReminderWeeklyOffset = newValue }
    }
    var notifExtraCredits: Bool {
        get { notification.extraCredits } set { notification.extraCredits = newValue }
    }
    var notifTokenExpired: Bool {
        get { notification.tokenExpired } set { notification.tokenExpired = newValue }
    }

    // Refresh interval (seconds) - minimum 180 (3min), default 300 (5min)
    @Published var refreshInterval: Int {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }

    // MARK: - Service status (outage monitoring)
    /// Master gate for outage monitoring. When false the poll loop never runs
    /// and the menu-bar badge never appears.
    @Published var outageMonitoringEnabled: Bool {
        didSet { UserDefaults.standard.set(outageMonitoringEnabled, forKey: "outageMonitoringEnabled") }
    }
    /// Healthy-state status poll cadence in seconds. Checks auto-accelerate to
    /// 60s during an outage regardless of this value.
    @Published var statusPollInterval: Int {
        didSet { UserDefaults.standard.set(statusPollInterval, forKey: "statusPollInterval") }
    }
    /// Whether to show the outage badge + countdown in the menu bar.
    @Published var statusShowMenuBarBadge: Bool {
        didSet { UserDefaults.standard.set(statusShowMenuBarBadge, forKey: "statusShowMenuBarBadge") }
    }
    /// Notify when a vendor goes degraded/down.
    var notifVendorDegraded: Bool {
        get { notification.vendorDegraded } set { notification.vendorDegraded = newValue }
    }
    /// Notify when a vendor recovers.
    var notifVendorRestored: Bool {
        get { notification.vendorRestored } set { notification.vendorRestored = newValue }
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

        self.pacing = PacingSettingsStore(sharedFileService: sharedFileService)
        self.notification = NotificationSettingsStore()
        self.overlay = OverlaySettingsStore()
        self.display = DisplaySettingsStore(sharedFileService: sharedFileService)

        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.proxyEnabled = UserDefaults.standard.bool(forKey: "proxyEnabled")
        self.proxyHost = UserDefaults.standard.string(forKey: "proxyHost") ?? "127.0.0.1"
        self.proxyPort = {
            let port = UserDefaults.standard.integer(forKey: "proxyPort")
            return port > 0 ? port : 1080
        }()
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
        self.refreshInterval = {
            let val = UserDefaults.standard.integer(forKey: "refreshInterval")
            return val >= 180 ? val : 300
        }()
        self.outageMonitoringEnabled = SettingsDefaults.bool(key: "outageMonitoringEnabled", default: true)
        self.statusPollInterval = {
            let val = UserDefaults.standard.integer(forKey: "statusPollInterval")
            return val >= 60 ? val : 300
        }()
        self.statusShowMenuBarBadge = SettingsDefaults.bool(key: "statusShowMenuBarBadge", default: true)

        // Popover layout config. Fresh install or decode failure -> defaults
        // that reproduce the v4.10.x popover visually (Classic variant, all
        // blocks visible).
        if let data = UserDefaults.standard.data(forKey: "popoverConfig"),
           let decoded = try? JSONDecoder().decode(PopoverConfig.self, from: data) {
            self.popoverConfig = Self.reconcile(decoded)
        } else {
            self.popoverConfig = .default
        }

        // The piège: a @Published child only emits the parent's objectWillChange
        // when reassigned, not when one of ITS @Published changes. Relay it so a
        // view observing `settings` re-renders on `settings.pacing.*` changes.
        // Wired after all stored properties are initialized so the closure can
        // safely capture self.
        self.pacingRelay = pacing.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        self.notificationRelay = notification.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        self.overlayRelay = overlay.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        self.displayRelay = display.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Popover persistence

    private func savePopoverConfig() {
        guard let data = try? JSONEncoder().encode(popoverConfig) else { return }
        UserDefaults.standard.set(data, forKey: "popoverConfig")
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

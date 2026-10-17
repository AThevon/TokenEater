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
    var displayFable: Bool {
        get { display.displayFable } set { display.displayFable = newValue }
    }
    /// Same as `displayFable` but for the paid Extra Credits pool. Only
    /// surfaced in settings when `UsageStore.hasExtraCredits` is true.
    var displayExtraCredits: Bool {
        get { display.displayExtraCredits } set { display.displayExtraCredits = newValue }
    }

    // MARK: - Popover
    /// The composable popover: one ordered list of elements (kind + style +
    /// width). Persisted as JSON under `popoverComposition` in UserDefaults.
    /// The legacy `popoverConfig` blob is migrated once (see init) and left
    /// in place so a downgrade restores the pre-5.9 popover untouched.
    /// The layout slice on screen. One live mode for the whole app, so the
    /// Studio selector and the popover selector are the same piece of state
    /// and an editor can never be showing a mode the app is not in.
    ///
    /// Switching persists the outgoing mode's layout, then loads the incoming
    /// one, seeding it on first visit from the All layout filtered to that
    /// provider. Seeding by plain copy is deliberately avoided: it would put
    /// Codex cells in the Claude mode, which is the unreadable popover the
    /// modes exist to fix.
    /// Claude tracking. Symmetric with `codexEnabled` on purpose: a ChatGPT
    /// subscriber with no Claude plan is a legitimate configuration, and the
    /// app has no business polling a provider that person does not use.
    ///
    /// The invariant the UI must hold, not this store: never let the user turn
    /// off the last active provider. The store allows it so the state stays
    /// simple, and `activeProviders` reports the truth either way.
    @Published var claudeEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(claudeEnabled, forKey: "claudeEnabled")
            reconcileProviderMode()
        }
    }

    /// Providers the user is actually tracking, in display order.
    var activeProviders: [MetricProvider] {
        var providers: [MetricProvider] = []
        if claudeEnabled { providers.append(.claude) }
        if codexEnabled { providers.append(.codex) }
        return providers
    }

    /// Modes worth offering: All plus one per active provider, and nothing at
    /// all below two providers, where All and the single provider describe the
    /// same thing.
    var availableProviderModes: [ProviderMode] {
        let providers = activeProviders
        guard providers.count > 1 else { return [] }
        return [.all] + providers.compactMap { provider in
            ProviderMode.allCases.first { $0.provider == provider }
        }
    }

    @Published var activeProviderMode: ProviderMode = .all {
        didSet {
            guard !isSwitchingScope, oldValue != activeProviderMode else { return }
            transitionScope(
                fromSuffix: Self.compositionSuffix(mode: oldValue, account: focusedClaudeAccount),
                to: activeProviderMode,
                account: focusedClaudeAccount
            )
        }
    }

    // MARK: - Claude accounts

    /// Every tracked Claude account, main first, as `AccountsStore` persists
    /// them. Loaded here synchronously so the mode and the compositions are
    /// restored for the right account before anything renders.
    @Published var claudeAccounts: [ClaudeAccountSummary] {
        didSet {
            guard claudeAccounts != oldValue else { return }
            reconcileProviderMode()
        }
    }

    /// The account Claude mode shows. Kept while another mode is on, so going
    /// back to Claude lands on the same account.
    @Published private(set) var focusedClaudeAccount: AccountID = .main

    /// Set while `selectScope` assigns the mode, so the mode's own `didSet`
    /// does not run a second transition.
    private var isSwitchingScope = false

    /// The accounts that are running: not paused, and Claude switched on.
    var activeClaudeAccounts: [ClaudeAccountSummary] {
        guard claudeEnabled else { return [] }
        return claudeAccounts.filter { !$0.isPaused }
    }

    /// The pills of the mode switcher: All, one per running Claude account,
    /// Codex. Empty below two, where All already says everything.
    var modeChoices: [ModeChoice] {
        var choices = activeClaudeAccounts.map { ModeChoice(mode: .claude, account: $0.id) }
        if codexEnabled { choices.append(ModeChoice(mode: .codex)) }
        guard choices.count > 1 else { return [] }
        return [ModeChoice(mode: .all)] + choices
    }

    /// The key suffix of the compositions on screen: the mode's, plus the
    /// focused account's in Claude mode. The main account adds nothing, so a
    /// single-account install reads and writes exactly the 6.0 keys.
    var compositionSuffix: String {
        Self.compositionSuffix(mode: activeProviderMode, account: focusedClaudeAccount)
    }

    static func compositionSuffix(mode: ProviderMode, account: AccountID) -> String {
        mode.storageSuffix + (mode == .claude ? account.storageSuffix : "")
    }

    /// Switches mode and, for Claude, the account, in one step: the outgoing
    /// layouts are saved under their own key before the incoming ones load,
    /// so a layout can never be filed under the wrong mode or account.
    func selectScope(_ mode: ProviderMode, account: AccountID = .main) {
        let target = mode == .claude ? account : focusedClaudeAccount
        let oldSuffix = compositionSuffix
        guard mode != activeProviderMode || target != focusedClaudeAccount else { return }
        transitionScope(fromSuffix: oldSuffix, to: mode, account: target)
    }

    private func transitionScope(fromSuffix oldSuffix: String, to mode: ProviderMode, account: AccountID) {
        let newSuffix = Self.compositionSuffix(mode: mode, account: account)
        // The published layouts still hold the outgoing scope's. Each surface
        // saves itself on change, so this only matters when the key moves.
        if newSuffix != oldSuffix { persistCompositions(suffix: oldSuffix) }
        // `activeProviderMode` may already hold `mode`: its own didSet is how
        // a plain assignment gets here.
        let accountChanged = focusedClaudeAccount != account
        isSwitchingScope = true
        if activeProviderMode != mode { activeProviderMode = mode }
        if accountChanged { focusedClaudeAccount = account }
        isSwitchingScope = false
        if newSuffix != oldSuffix {
            loadCompositions(suffix: newSuffix, mode: mode, account: account)
        }
        if UserDefaults.standard.string(forKey: "activeProviderMode") != mode.rawValue {
            UserDefaults.standard.set(mode.rawValue, forKey: "activeProviderMode")
        }
        if accountChanged {
            if account.isMain {
                UserDefaults.standard.removeObject(forKey: Self.focusedAccountKey)
            } else {
                UserDefaults.standard.set(account.rawValue, forKey: Self.focusedAccountKey)
            }
        }
    }

    private static let focusedAccountKey = "focusedClaudeAccount"

    /// Points Claude mode back at the main account, whatever mode is on.
    private func resetFocusToMain() {
        guard !focusedClaudeAccount.isMain else { return }
        transitionScope(fromSuffix: compositionSuffix, to: activeProviderMode, account: .main)
    }

    /// The `heroWindows` key of an account's glance card. The main account
    /// keeps the provider's bare key, so its choice survives untouched.
    func heroWindowKey(_ provider: MetricProvider, account: AccountID = .main) -> String {
        provider == .claude ? provider.rawValue + account.storageSuffix : provider.rawValue
    }

    /// The All mode's menu bar layout, whichever mode is on screen: the
    /// published one in All, the stored one otherwise.
    var allModeMenuBarComposition: MenuBarComposition {
        if activeProviderMode == .all { return menuBarComposition }
        return UserDefaults.standard.data(forKey: "menuBarComposition" + ProviderMode.all.storageSuffix)
            .flatMap { try? JSONDecoder().decode(MenuBarComposition.self, from: $0) }
            ?? Self.seededMenuBar(for: .all)
    }

    /// Gives a newly added account its place in the All layouts: always a
    /// compact section in the popover, and its session and weekly segments in
    /// the menu bar when the user kept "Add to the menu bar" checked. When All
    /// is not the mode on screen, its stored layout is updated in place and
    /// the one on screen is left alone. The account's own Claude mode layouts
    /// are seeded later, on its first visit.
    func seedAccount(_ id: AccountID, addToMenuBar: Bool) {
        guard !id.isMain else { return }
        if activeProviderMode == .all {
            popoverComposition = popoverComposition.addingAccountSection(id)
            if addToMenuBar {
                menuBarComposition = menuBarComposition.addingAccountSegments(id)
            }
            return
        }
        let defaults = UserDefaults.standard
        let popoverKey = "popoverComposition" + ProviderMode.all.storageSuffix
        let storedPopover = defaults.data(forKey: popoverKey)
            .flatMap { try? JSONDecoder().decode(PopoverComposition.self, from: $0) }
            .map(Self.reconcile) ?? Self.seededPopover(for: .all)
        if let data = try? JSONEncoder().encode(storedPopover.addingAccountSection(id)) {
            defaults.set(data, forKey: popoverKey)
        }
        guard addToMenuBar else { return }
        let menuBarKey = "menuBarComposition" + ProviderMode.all.storageSuffix
        if let data = try? JSONEncoder().encode(allModeMenuBarComposition.addingAccountSegments(id)) {
            defaults.set(data, forKey: menuBarKey)
        }
    }

    /// Forgets everything stored for a removed account: its own mode's
    /// layouts, every segment and element that targeted it (saved layouts and
    /// templates included), and its glance card choice.
    func purgeAccount(_ id: AccountID) {
        guard !id.isMain else { return }
        if focusedClaudeAccount == id { resetFocusToMain() }

        let defaults = UserDefaults.standard
        let ownSuffix = ProviderMode.claude.storageSuffix + id.storageSuffix
        for base in ["popoverComposition", "menuBarComposition", "dashboardComposition"] {
            defaults.removeObject(forKey: base + ownSuffix)
        }

        for key in defaults.dictionaryRepresentation().keys {
            if key == "popoverComposition" || key.hasPrefix("popoverComposition.") {
                guard let data = defaults.data(forKey: key),
                      var decoded = try? JSONDecoder().decode(PopoverComposition.self, from: data),
                      decoded.elements.contains(where: { $0.account == id }) else { continue }
                decoded.elements.removeAll { $0.account == id }
                if let encoded = try? JSONEncoder().encode(decoded) { defaults.set(encoded, forKey: key) }
            } else if key == "menuBarComposition" || key.hasPrefix("menuBarComposition.") {
                guard let data = defaults.data(forKey: key),
                      var decoded = try? JSONDecoder().decode(MenuBarComposition.self, from: data),
                      decoded.segments.contains(where: { $0.account == id }) else { continue }
                decoded.segments.removeAll { $0.account == id }
                if let encoded = try? JSONEncoder().encode(decoded) { defaults.set(encoded, forKey: key) }
            }
        }

        if popoverComposition.elements.contains(where: { $0.account == id }) {
            var next = popoverComposition
            next.elements.removeAll { $0.account == id }
            popoverComposition = Self.reconcile(next)
        }
        if menuBarComposition.segments.contains(where: { $0.account == id }) {
            var next = menuBarComposition
            next.segments.removeAll { $0.account == id }
            menuBarComposition = next
        }
        if popoverUserTemplates.contains(where: { $0.composition.elements.contains { $0.account == id } }) {
            popoverUserTemplates = popoverUserTemplates.map { template in
                var template = template
                template.composition.elements.removeAll { $0.account == id }
                return template
            }
        }
        if menuBarUserTemplates.contains(where: { $0.composition.segments.contains { $0.account == id } }) {
            menuBarUserTemplates = menuBarUserTemplates.map { template in
                var template = template
                template.composition.segments.removeAll { $0.account == id }
                return template
            }
        }

        let heroKey = heroWindowKey(.claude, account: id)
        if heroWindows[heroKey] != nil {
            var next = heroWindows
            next.removeValue(forKey: heroKey)
            heroWindows = next
        }
    }

    /// The dashboard's block order and visibility, per provider mode.
    ///
    /// Same key scheme as the popover and the menu bar, so All keeps the bare
    /// key and a provider mode gets a suffix. Its default reproduces the
    /// layout the page has always had, which is what makes turning the
    /// dashboard composable a no-op for anyone who never opens the editor.
    @Published var dashboardComposition: DashboardComposition {
        didSet { saveDashboardComposition() }
    }

    @Published var popoverComposition: PopoverComposition {
        didSet { savePopoverComposition() }
    }
    /// Compositions the user saved under a name from the popover editor.
    @Published var popoverUserTemplates: [PopoverUserTemplate] {
        didSet { savePopoverUserTemplates() }
    }

    // MARK: - Menu bar
    /// The composable menu bar: one ordered list of segments (kind + style).
    /// Persisted as JSON under `menuBarComposition`. The legacy `pinnedMetrics`
    /// + `menuBarStyle` + per-metric display prefs are migrated once (see init)
    /// and left in place so a downgrade restores the pre-5.10 menu bar.
    @Published var menuBarComposition: MenuBarComposition {
        didSet { saveMenuBarComposition() }
    }
    /// Compositions the user saved under a name from the menu bar editor.
    @Published var menuBarUserTemplates: [MenuBarUserTemplate] {
        didSet { saveMenuBarUserTemplates() }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
            // Someone who just finished the wizard has seen this release's
            // features in it, so the what's-new screen would be the second
            // full-screen takeover in a row for a release they were not here
            // for. Replaying the wizard later does not re-arm it either.
            if hasCompletedOnboarding, !oldValue { markWhatsNewSeen() }
        }
    }

    /// One-shot discovery flag for the Studio intro (nav bubble + what's-new
    /// sheet). Flips true the first time the user sees, dismisses, or reaches
    /// the Studio; also set on onboarding completion so fresh installs never
    /// get an upgrade pitch for a feature they onboarded with.
    @Published var hasSeenStudioIntro: Bool {
        didSet { UserDefaults.standard.set(hasSeenStudioIntro, forKey: "hasSeenStudioIntro") }
    }

    // MARK: - Providers

    /// Whether Codex usage is tracked at all. Auto-enabled once, on the first
    /// launch that finds a ChatGPT login in `~/.codex/auth.json`, so existing
    /// Codex users get the feature without hunting for a switch and everyone
    /// else sees no change. A later login does not flip it by itself; the
    /// Providers card offers the toggle instead.
    @Published var codexEnabled: Bool {
        didSet {
            UserDefaults.standard.set(codexEnabled, forKey: "codexEnabled")
            reconcileProviderMode()
        }
    }

    /// Whether the popover shows the provider switcher.
    ///
    /// Global on purpose, and not a composable element any more. As an element
    /// it lived inside each mode's layout, so switching to a mode whose layout
    /// did not contain it removed the only way back out of that mode: the
    /// control that changes the scope cannot be something the scope can
    /// delete. One preference, every mode, still yours to turn off.
    @Published var popoverShowsProviderSwitch: Bool {
        didSet { UserDefaults.standard.set(popoverShowsProviderSwitch, forKey: "popoverShowsProviderSwitch") }
    }

    /// The app version whose what's-new screen the user has already seen.
    ///
    /// Empty on a fresh install, which is deliberate: `needsWhatsNew` is gated
    /// on onboarding being done, so a new user gets the wizard and never the
    /// release notes for a release they were not here for.
    @Published var lastSeenVersion: String {
        didSet { UserDefaults.standard.set(lastSeenVersion, forKey: "lastSeenVersion") }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Compared on major.minor only: a patch release has nothing to announce,
    /// and putting a full-screen takeover in front of a bug fix is how a
    /// what's-new screen turns into something people learn to dismiss blind.
    var needsWhatsNew: Bool {
        guard hasCompletedOnboarding else { return false }
        func minorOf(_ version: String) -> String {
            version.split(separator: ".").prefix(2).joined(separator: ".")
        }
        return minorOf(lastSeenVersion) != minorOf(Self.currentVersion)
    }

    func markWhatsNewSeen() {
        lastSeenVersion = Self.currentVersion
    }

    /// Which window each provider's glance card shows, keyed by provider.
    /// A provider absent from the map is on automatic, which means the
    /// shortest window it actually has: the 5-hour one where it exists, the
    /// weekly one where it does not. That rule is why the two cards used to
    /// disagree - Claude was pinned to 5h and Codex picked whichever window
    /// was closest to its cap, so on a Pro plan with no 5h window one card
    /// silently answered a different question from the other.
    ///
    /// One map rather than a property per provider, so a third provider
    /// stores its choice without a schema change.
    @Published var heroWindows: [String: String] {
        didSet {
            guard let data = try? JSONEncoder().encode(heroWindows) else { return }
            UserDefaults.standard.set(data, forKey: "heroWindows")
        }
    }


    /// Puts the app back in All when the mode points at a provider that is no
    /// longer on.
    ///
    /// Without it, turning Claude off while the app was in Claude mode left
    /// `visibleProviders` empty and the dashboard rendered nothing at all:
    /// the mode filtered for a provider `activeProviders` no longer contained,
    /// and no surface had anything to draw. A mode is a view of what is on, so
    /// it cannot outlive what it was a view of.
    /// Deliberately not widened to `availableProviderModes`: dropping to a
    /// single provider leaves that provider's mode describing exactly what is
    /// on, so it stands, with its own layout, and the selector simply has
    /// nothing left to offer. Only a mode pointing at a provider that is off
    /// is incoherent.
    ///
    /// The same goes for an account: Claude mode pointed at an account that
    /// was paused or removed goes back to the main account, its layout saved
    /// first.
    private func reconcileProviderMode() {
        if !focusedClaudeAccount.isMain,
           !claudeAccounts.contains(where: { $0.id == focusedClaudeAccount && !$0.isPaused }) {
            resetFocusToMain()
        }
        guard let provider = activeProviderMode.provider else { return }
        guard !activeProviders.contains(provider) else { return }
        activeProviderMode = .all
    }

    func heroWindow(for provider: MetricProvider, account: AccountID = .main) -> String? {
        heroWindows[heroWindowKey(provider, account: account)]
    }

    /// Nil puts the provider back on automatic and removes the key entirely,
    /// so "automatic" is the absence of a choice rather than a stored value
    /// that a later change of default would silently override.
    func setHeroWindow(_ window: String?, for provider: MetricProvider, account: AccountID = .main) {
        let key = heroWindowKey(provider, account: account)
        var next = heroWindows
        if let window { next[key] = window } else { next.removeValue(forKey: key) }
        heroWindows = next
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
    var notifCodexEnabled: Bool {
        get { notification.codexEnabled } set { notification.codexEnabled = newValue }
    }
    var notifCodexWindowReset: Bool {
        get { notification.codexWindowReset } set { notification.codexWindowReset = newValue }
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

    /// Decides the Codex toggle on first launch and honours the user's choice
    /// afterwards. The probe runs exactly once per install (guarded by its own
    /// flag), so a user who turns Codex off does not get it turned back on by
    /// the next launch, and someone who logs into Codex later is offered the
    /// toggle in Settings rather than having it flipped under them.
    ///
    /// Expiry is part of the probe on purpose. `isTrackable` only says the
    /// credential is a ChatGPT one, not that it still works, and only the
    /// Codex CLI refreshes it. Auto-enabling on a stale credential would poll,
    /// fail, and notify about a login the user never asked us to watch.
    private static func resolveCodexEnabled(authStateProvider: () -> CodexAuthState) -> Bool {
        if let stored = UserDefaults.standard.object(forKey: "codexEnabled") as? Bool { return stored }
        let state = authStateProvider()
        let detected = state.isTrackable && !state.isExpired()
        UserDefaults.standard.set(detected, forKey: "codexEnabled")
        return detected
    }

    init(
        notificationService: NotificationServiceProtocol = NotificationService(),
        tokenProvider: TokenProviderProtocol = TokenProvider.forMainAccount(),
        sharedFileService: SharedFileServiceProtocol = SharedFileService(),
        codexAuthStateProvider: @escaping () -> CodexAuthState = { CodexAuthReader().authState() }
    ) {
        self.notificationService = notificationService
        self.tokenProvider = tokenProvider
        self.sharedFileService = sharedFileService

        self.pacing = PacingSettingsStore(sharedFileService: sharedFileService)
        self.notification = NotificationSettingsStore()
        self.overlay = OverlaySettingsStore()
        // Local so the popover migration below can read the legacy display
        // toggles without touching `self` before init completes.
        let displayStore = DisplaySettingsStore(sharedFileService: sharedFileService)
        self.display = displayStore

        self.claudeAccounts = ClaudeAccountsStorage.load(from: .standard).map(\.summary)
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        self.hasSeenStudioIntro = UserDefaults.standard.bool(forKey: "hasSeenStudioIntro")
        self.codexEnabled = Self.resolveCodexEnabled(authStateProvider: codexAuthStateProvider)
        // Defaults to true so every existing install keeps tracking Claude.
        self.claudeEnabled = UserDefaults.standard.object(forKey: "claudeEnabled") as? Bool ?? true
        self.lastSeenVersion = UserDefaults.standard.string(forKey: "lastSeenVersion") ?? ""
        self.dashboardComposition = Self.loadDashboard(for: .all)
        self.popoverShowsProviderSwitch =
            UserDefaults.standard.object(forKey: "popoverShowsProviderSwitch") as? Bool ?? true
        self.heroWindows = UserDefaults.standard.data(forKey: "heroWindows")
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
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

        // Popover composition. Load order: new blob, else one-shot migration
        // of the legacy variant-based config (preserving what the user saw
        // before 5.9), else the Classic template. Whatever path produced it,
        // `PopoverChromeMigrator` then lifts a v1 result's fixed header
        // chrome into regular elements (no-op on v2).
        let hadCompositionBlob = UserDefaults.standard.data(forKey: "popoverComposition") != nil
        // Version the stored blob was written at -> when below current, the
        // chrome-migrated result must be persisted at the end of init
        // (didSet does not fire during init).
        var storedPopoverVersion = PopoverComposition.currentVersion
        if let data = UserDefaults.standard.data(forKey: "popoverComposition"),
           let decoded = try? JSONDecoder().decode(PopoverComposition.self, from: data) {
            storedPopoverVersion = decoded.version
            self.popoverComposition = PopoverChromeMigrator.migrate(Self.reconcile(decoded))
        } else if let legacy = UserDefaults.standard.data(forKey: "popoverConfig"),
                  let config = try? JSONDecoder().decode(PopoverConfig.self, from: legacy) {
            self.popoverComposition = PopoverChromeMigrator.migrate(Self.reconcile(PopoverConfigMigrator.migrate(
                config,
                displaySonnet: displayStore.displaySonnet,
                displayFable: displayStore.displayFable,
                displayExtraCredits: displayStore.displayExtraCredits,
                // Presence from the cached usage, so a stale toggle (metric
                // no longer on the account) can't flip the layout shape.
                presence: PopoverConfigMigrator.AccountPresence(
                    cachedUsage: sharedFileService.cachedUsage?.usage
                )
            )))
        } else {
            self.popoverComposition = .default
        }

        var popoverTemplatesChanged = false
        if let data = UserDefaults.standard.data(forKey: "popoverUserTemplates"),
           let decoded = try? JSONDecoder().decode([PopoverUserTemplate].self, from: data) {
            // Chrome-migrate any template saved before composition v2, so
            // applying it never resurrects the pre-element header state.
            let migrated = decoded.map { template in
                var template = template
                template.composition = PopoverChromeMigrator.migrate(template.composition)
                return template
            }
            self.popoverUserTemplates = migrated
            popoverTemplatesChanged = migrated != decoded
        } else {
            self.popoverUserTemplates = []
        }

        // Menu bar composition. New blob, else one-shot migration of the
        // legacy pinnedMetrics + menuBarStyle + per-metric display prefs
        // (preserving what the user saw before 5.10), else the Classic template.
        let hadMenuBarBlob = UserDefaults.standard.data(forKey: "menuBarComposition") != nil
        if let data = UserDefaults.standard.data(forKey: "menuBarComposition"),
           let decoded = try? JSONDecoder().decode(MenuBarComposition.self, from: data) {
            self.menuBarComposition = decoded
        } else {
            self.menuBarComposition = MenuBarConfigMigrator.migrate(
                pinnedMetrics: displayStore.pinnedMetrics,
                menuBarStyle: displayStore.menuBarStyle,
                sessionPacingDisplayMode: displayStore.sessionPacingDisplayMode,
                weeklyPacingDisplayMode: displayStore.weeklyPacingDisplayMode,
                resetDisplayFormat: displayStore.resetDisplayFormat,
                pacingShape: displayStore.pacingShape
            )
        }

        if let data = UserDefaults.standard.data(forKey: "menuBarUserTemplates"),
           let decoded = try? JSONDecoder().decode([MenuBarUserTemplate].self, from: data) {
            self.menuBarUserTemplates = decoded
        } else {
            self.menuBarUserTemplates = []
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

        // didSet doesn't fire during init - persist the migrated / default
        // compositions now so the one-shot migrations are durable.
        if !hadCompositionBlob || storedPopoverVersion < PopoverComposition.currentVersion {
            savePopoverComposition()
        }
        if popoverTemplatesChanged {
            savePopoverUserTemplates()
        }
        if !hadMenuBarBlob {
            saveMenuBarComposition()
        }

        // Last, and after those one-shot saves on purpose: they persist the
        // migrated layout, and until this point the mode is still `.all`, so
        // they land under the pre-modes keys where they belong. Restoring
        // earlier would file a migrated All layout under a provider mode's key.
        //
        // The backing store is assigned directly so the didSet does not write
        // the All layout under the restored mode's key before that mode's own
        // layout has been read; `loadCompositions` then does the read, and its
        // assignments persist the seeded layout on a first visit.
        //
        // The focused account is restored the same way, and only while it is
        // still running: a paused or removed one leaves Claude mode on the
        // main account, whose layout lives under the plain `.claude` key.
        let restoredMode = UserDefaults.standard.string(forKey: "activeProviderMode")
            .flatMap(ProviderMode.init(rawValue:)) ?? .all
        let restoredAccount = UserDefaults.standard.string(forKey: Self.focusedAccountKey)
            .map(AccountID.init(rawValue:))
            .flatMap { id in claudeAccounts.contains { $0.id == id && !$0.isPaused } ? id : nil }
            ?? .main
        if !restoredAccount.isMain {
            self._focusedClaudeAccount = Published(initialValue: restoredAccount)
        }
        if restoredMode != .all {
            self._activeProviderMode = Published(initialValue: restoredMode)
            loadCompositions(suffix: compositionSuffix, mode: restoredMode, account: focusedClaudeAccount)
        }
    }

    // MARK: - Popover persistence

    private func savePopoverComposition() {
        guard let data = try? JSONEncoder().encode(popoverComposition) else { return }
        UserDefaults.standard.set(data, forKey: "popoverComposition" + compositionSuffix)
    }

    // MARK: - Provider modes

    /// Writes both surfaces under the given mode's keys. Called with the
    /// OUTGOING mode on a switch, since the published values still hold its
    /// layout at that point.
    private func saveDashboardComposition() {
        guard let data = try? JSONEncoder().encode(dashboardComposition) else { return }
        UserDefaults.standard.set(data, forKey: "dashboardComposition" + compositionSuffix)
    }

    static func loadDashboard(for mode: ProviderMode) -> DashboardComposition {
        loadDashboard(suffix: mode.storageSuffix) ?? .default
    }

    private static func loadDashboard(suffix: String) -> DashboardComposition? {
        guard let data = UserDefaults.standard.data(forKey: "dashboardComposition" + suffix),
              let decoded = try? JSONDecoder().decode(DashboardComposition.self, from: data),
              !decoded.entries.isEmpty
        else { return nil }
        return DashboardComposition.reconciled(decoded)
    }

    private func persistCompositions(suffix: String) {
        if let data = try? JSONEncoder().encode(popoverComposition) {
            UserDefaults.standard.set(data, forKey: "popoverComposition" + suffix)
        }
        if let data = try? JSONEncoder().encode(menuBarComposition) {
            UserDefaults.standard.set(data, forKey: "menuBarComposition" + suffix)
        }
        if let data = try? JSONEncoder().encode(dashboardComposition) {
            UserDefaults.standard.set(data, forKey: "dashboardComposition" + suffix)
        }
    }

    /// Loads both surfaces for a mode, seeding from the All layout the first
    /// time a mode is visited. A key that has never been written is the
    /// nominal case, not an error: modes are created lazily so an install that
    /// never leaves All keeps exactly the keys it had before modes existed.
    private func loadCompositions(suffix: String, mode: ProviderMode, account: AccountID) {
        // Self-healing: a layout saved by an older build, or one whose only
        // metrics belong to the other provider, would render an empty
        // popover. An empty surface reads as a broken app, so a mode with
        // nothing of its own left is re-seeded rather than shown hollow.
        //
        // The test is "carries at least one element belonging to a provider
        // this mode shows", not "carries a percentage": a pacing-only or
        // watchers-only layout is a legitimate choice, and the built-in Pace
        // template is exactly one, so requiring a usage element here would
        // silently overwrite it on every mode switch.
        let popoverKey = "popoverComposition" + suffix
        if let data = UserDefaults.standard.data(forKey: popoverKey),
           let decoded = try? JSONDecoder().decode(PopoverComposition.self, from: data),
           decoded.elements.contains(where: { element in
               guard let provider = element.kind.provider else { return false }
               return mode.shows(provider)
           }) {
            popoverComposition = Self.reconcile(decoded)
        } else {
            popoverComposition = Self.seededPopover(for: mode, account: account)
        }

        // An added account's dashboard starts as the main account's Claude
        // one: same blocks, same order, its own numbers.
        dashboardComposition = Self.loadDashboard(suffix: suffix)
            ?? (account.isMain || mode != .claude ? nil : Self.loadDashboard(suffix: mode.storageSuffix))
            ?? .default

        let menuBarKey = "menuBarComposition" + suffix
        if let data = UserDefaults.standard.data(forKey: menuBarKey),
           let decoded = try? JSONDecoder().decode(MenuBarComposition.self, from: data),
           decoded.segments.contains(where: { mode.shows($0.kind.provider) }) {
            menuBarComposition = decoded
        } else {
            menuBarComposition = Self.seededMenuBar(for: mode, account: account)
        }
    }

    /// Claude mode shows one account. Elements and segments pinned to
    /// another account make no sense there, and those pinned to this one
    /// need no pin, so a seeded Claude layout keeps only the unpinned ones.
    private static func keepsInClaudeMode(_ account: AccountID?, focused: AccountID) -> Bool {
        account == nil || account == focused
    }

    /// The All layout, kept under the pre-modes key, filtered to the mode's
    /// provider. Chrome, utilities and actions carry no provider and survive
    /// every filter, so a seeded mode is never an empty shell.
    private static func seededPopover(for mode: ProviderMode, account: AccountID = .main) -> PopoverComposition {
        // An added account copies the main account's Claude layout when
        // there is one, so its mode looks like Claude's from the first visit.
        if mode == .claude, !account.isMain,
           let data = UserDefaults.standard.data(forKey: "popoverComposition" + mode.storageSuffix),
           let decoded = try? JSONDecoder().decode(PopoverComposition.self, from: data),
           decoded.elements.contains(where: { $0.kind.provider == .claude }) {
            var seeded = reconcile(decoded)
            seeded.elements = seeded.elements
                .filter { mode.shows($0.kind.provider) && keepsInClaudeMode($0.account, focused: .main) }
                .map { var element = $0; element.account = nil; return element }
            return seeded.elements.isEmpty ? .default : seeded
        }
        let base: PopoverComposition = {
            guard let data = UserDefaults.standard.data(forKey: "popoverComposition"),
                  let decoded = try? JSONDecoder().decode(PopoverComposition.self, from: data)
            else { return .default }
            return reconcile(decoded)
        }()
        var seeded = base
        seeded.elements = base.elements.filter {
            mode.shows($0.kind.provider)
                && (mode != .claude || keepsInClaudeMode($0.account, focused: .main))
        }
        if mode == .claude {
            seeded.elements = seeded.elements.map { var element = $0; element.account = nil; return element }
        }
        // A provider the user has never placed leaves only chrome behind.
        // Start from the built-in instead of handing them an empty popover.
        // Both single-provider modes need this: an All layout built entirely
        // out of Codex elements strands Claude mode exactly the same way.
        let hasMetric = seeded.elements.contains { $0.kind.provider != nil }
        if !hasMetric, mode.provider != nil {
            seeded.elements = PopoverBuiltinTemplate.sideBySide.composition.elements
                .filter { mode.shows($0.kind.provider) }
        }
        return seeded.elements.isEmpty ? .default : seeded
    }

    private static func seededMenuBar(for mode: ProviderMode, account: AccountID = .main) -> MenuBarComposition {
        if mode == .claude, !account.isMain,
           let data = UserDefaults.standard.data(forKey: "menuBarComposition" + mode.storageSuffix),
           let decoded = try? JSONDecoder().decode(MenuBarComposition.self, from: data),
           decoded.segments.contains(where: { $0.kind.provider == .claude }) {
            var seeded = decoded
            seeded.segments = decoded.segments
                .filter { mode.shows($0.kind.provider) && keepsInClaudeMode($0.account, focused: .main) }
                .map { var segment = $0; segment.account = nil; return segment }
            return seeded.segments.isEmpty ? .default : seeded
        }
        let base: MenuBarComposition = {
            guard let data = UserDefaults.standard.data(forKey: "menuBarComposition"),
                  let decoded = try? JSONDecoder().decode(MenuBarComposition.self, from: data)
            else { return .default }
            return decoded
        }()
        var seeded = base
        seeded.segments = base.segments.filter {
            mode.shows($0.kind.provider)
                && (mode != .claude || keepsInClaudeMode($0.account, focused: .main))
        }
        if mode == .claude {
            seeded.segments = seeded.segments.map { var segment = $0; segment.account = nil; return segment }
        }
        if seeded.segments.isEmpty, mode == .codex {
            seeded.segments = [
                MenuBarSegment(kind: .codexSession, style: .labelValue),
                MenuBarSegment(kind: .codexWeekly, style: .labelValue),
            ]
        }
        return seeded.segments.isEmpty ? .default : seeded
    }

    private func savePopoverUserTemplates() {
        guard let data = try? JSONEncoder().encode(popoverUserTemplates) else { return }
        UserDefaults.standard.set(data, forKey: "popoverUserTemplates")
    }

    // MARK: - Menu bar persistence

    private func saveMenuBarComposition() {
        guard let data = try? JSONEncoder().encode(menuBarComposition) else { return }
        UserDefaults.standard.set(data, forKey: "menuBarComposition" + compositionSuffix)
    }

    private func saveMenuBarUserTemplates() {
        guard let data = try? JSONEncoder().encode(menuBarUserTemplates) else { return }
        UserDefaults.standard.set(data, forKey: "menuBarUserTemplates")
    }

    /// Ensures a decoded composition still satisfies the validation rules
    /// (at least one visible element). Anything off falls back to the default
    /// template rather than rendering an empty popover.
    private static func reconcile(_ composition: PopoverComposition) -> PopoverComposition {
        composition.hasVisibleContent ? composition : .default
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

    func sendTestNotification(for provider: MetricProvider? = nil) {
        notificationService.sendTest(for: provider)
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

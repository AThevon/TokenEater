import SwiftUI
import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    var historyWidgetStore: HistoryWidgetStore!
    var codexStore: CodexUsageStore!
    var usageStore: UsageStore!
    var themeStore: ThemeStore!
    var settingsStore: SettingsStore!
    var updateStore: UpdateStore!
    var sessionStore: SessionStore!
    var vendorStatusStore: VendorStatusStore!
    var accountsStore: AccountsStore!

    private var statusBarController: StatusBarController?
    private var overlayWindowController: OverlayWindowController?
    private var monitorCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        NotificationCenter.default.post(name: .openDashboard, object: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clean up the v4.x LaunchAgent helper on first launch after upgrade.
        // Idempotent + gated by a UserDefaults flag, so this is effectively a
        // no-op for fresh installs and for subsequent launches of upgraded users.
        LegacyHelperCleanupService().runIfNeeded()

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        statusBarController = StatusBarController(
            usageStore: usageStore,
            codexStore: codexStore,
            themeStore: themeStore,
            settingsStore: settingsStore,
            updateStore: updateStore,
            sessionStore: sessionStore,
            vendorStatusStore: vendorStatusStore,
            accountsStore: accountsStore
        )
        // Apply persisted watcher scan settings before the first tick uses them.
        sessionStore.setScanInterval(settingsStore.watcherScanInterval.seconds)
        sessionStore.setVisibility(settingsStore.watcherVisibility.seconds)
        if settingsStore.overlayEnabled {
            sessionStore.startMonitoring()
        }
        overlayWindowController = OverlayWindowController(
            sessionStore: sessionStore,
            settingsStore: settingsStore
        )

        historyWidgetStore.start()
        // The sparkline sums every tracked account's transcripts; when the
        // main account's folder moves (#294) or an account comes or goes,
        // the next five-minute pass would be too late.
        Publishers.Merge(
            accountsStore.mainScopeChanged.map { _ in () },
            accountsStore.$records.map { $0.map(\.id) }.removeDuplicates().dropFirst().map { _ in () }
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let store = self?.historyWidgetStore else { return }
                Task { @MainActor in await store.refresh() }
            }
            .store(in: &cancellables)

        updateStore.checkBrewMigration()
        updateStore.checkForUpdates()

        monitorCancellable = settingsStore.overlay.$overlayEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.sessionStore.startMonitoring()
                } else {
                    self.sessionStore.stopMonitoring()
                }
            }

        settingsStore.overlay.$watcherScanInterval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] interval in
                self?.sessionStore.setScanInterval(interval.seconds)
            }
            .store(in: &cancellables)

        settingsStore.overlay.$watcherVisibility
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] visibility in
                self?.sessionStore.setVisibility(visibility.seconds)
            }
            .store(in: &cancellables)
    }
}

@main
struct TokenEaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let historyWidgetStore: HistoryWidgetStore
    private let codexStore: CodexUsageStore
    private let usageStore: UsageStore
    private let themeStore: ThemeStore
    private let settingsStore: SettingsStore
    private let updateStore: UpdateStore
    private let sessionStore: SessionStore
    private let vendorStatusStore: VendorStatusStore
    private let accountsStore: AccountsStore

    init() {
        // NSRunningApplication only enumerates the current login session, so this
        // refuses a second launch by the same user without blocking a separate
        // macOS user's own instance (e.g. under Fast User Switching).
        if let bundleID = Bundle.main.bundleIdentifier {
            let currentPID = ProcessInfo.processInfo.processIdentifier
            if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0.processIdentifier != currentPID }) {
                existing.activate()
                exit(0)
            }
        }

        // Migrate v4.x sandbox-container UserDefaults into the real path BEFORE
        // any store is constructed - store inits read UserDefaults.standard, so
        // missing this step would make every upgrading user land on onboarding.
        LegacyHelperCleanupService().migratePrefsIfNeeded()

        self.historyWidgetStore = HistoryWidgetStore()
        self.codexStore = CodexUsageStore()
        // The main account's store reads the folder the user chose for it,
        // `~/.claude` unless they chose another one (#294).
        let mainNotifications = NotificationService()
        let usageStore = UsageStore(
            tokenProvider: TokenProvider.forMainAccount(),
            notificationService: mainNotifications
        )
        self.usageStore = usageStore
        let accountsStore = AccountsStore(mainStore: usageStore)
        self.accountsStore = accountsStore
        // The main account's alerts keep their historical identifiers and
        // only name the account once a second one runs; the scope that knows
        // when exists once the account list does.
        mainNotifications.scope = accountsStore.notificationScope(for: .main)
        self.themeStore = ThemeStore()
        self.settingsStore = SettingsStore()
        self.updateStore = UpdateStore()
        self.sessionStore = SessionStore()
        self.vendorStatusStore = VendorStatusStore()

        NotificationService().setupDelegate()
        appDelegate.historyWidgetStore = historyWidgetStore
        appDelegate.codexStore = codexStore
        appDelegate.usageStore = usageStore
        appDelegate.themeStore = themeStore
        appDelegate.settingsStore = settingsStore
        appDelegate.updateStore = updateStore
        appDelegate.sessionStore = sessionStore
        appDelegate.vendorStatusStore = vendorStatusStore
        appDelegate.accountsStore = accountsStore
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}


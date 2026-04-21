import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    var usageStore: UsageStore!
    var themeStore: ThemeStore!
    var settingsStore: SettingsStore!
    var updateStore: UpdateStore!
    var sessionStore: SessionStore!

    private var statusBarController: StatusBarController?
    private var overlayWindowController: OverlayWindowController?
    private var monitorCancellable: AnyCancellable?

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
            themeStore: themeStore,
            settingsStore: settingsStore,
            updateStore: updateStore,
            sessionStore: sessionStore
        )
        if settingsStore.sessionMonitorEnabled {
            sessionStore.startMonitoring()
        }
        overlayWindowController = OverlayWindowController(
            sessionStore: sessionStore,
            settingsStore: settingsStore
        )

        updateStore.checkBrewMigration()
        updateStore.checkForUpdates()

        monitorCancellable = settingsStore.$sessionMonitorEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.sessionStore.startMonitoring()
                } else {
                    self.sessionStore.stopMonitoring()
                }
            }
    }
}

@main
struct TokenEaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let usageStore: UsageStore
    private let themeStore: ThemeStore
    private let settingsStore: SettingsStore
    private let updateStore: UpdateStore
    private let sessionStore: SessionStore

    init() {
        // Migrate v4.x sandbox-container UserDefaults into the real path BEFORE
        // any store is constructed - store inits read UserDefaults.standard, so
        // missing this step would make every upgrading user land on onboarding.
        LegacyHelperCleanupService().migratePrefsIfNeeded()

        self.usageStore = UsageStore()
        self.themeStore = ThemeStore()
        self.settingsStore = SettingsStore()
        self.updateStore = UpdateStore()
        self.sessionStore = SessionStore()

        NotificationService().setupDelegate()
        appDelegate.usageStore = usageStore
        appDelegate.themeStore = themeStore
        appDelegate.settingsStore = settingsStore
        appDelegate.updateStore = updateStore
        appDelegate.sessionStore = sessionStore
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}


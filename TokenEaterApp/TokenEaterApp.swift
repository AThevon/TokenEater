import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var usageStore: UsageStore!
    var themeStore: ThemeStore!
    var settingsStore: SettingsStore!
    var updateStore: UpdateStore!
    var sessionStore: SessionStore!

    private var statusBarController: StatusBarController?
    private var overlayWindowController: OverlayWindowController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(
            usageStore: usageStore,
            themeStore: themeStore,
            settingsStore: settingsStore,
            updateStore: updateStore
        )
        sessionStore.startMonitoring()
        overlayWindowController = OverlayWindowController(
            sessionStore: sessionStore,
            settingsStore: settingsStore
        )
    }
}

@main
struct TokenEaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let usageStore = UsageStore()
    private let themeStore = ThemeStore()
    private let settingsStore = SettingsStore()
    private let updateStore = UpdateStore()
    private let sessionStore = SessionStore()

    init() {
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


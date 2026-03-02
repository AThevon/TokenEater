import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var usageStore: UsageStore!
    var themeStore: ThemeStore!
    var settingsStore: SettingsStore!
    var updateStore: UpdateStore!

    private var statusBarController: StatusBarController?

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
    }
}

@main
struct TokenEaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let usageStore = UsageStore()
    private let themeStore = ThemeStore()
    private let settingsStore = SettingsStore()
    private let updateStore = UpdateStore()

    init() {
        NotificationService().setupDelegate()
        appDelegate.usageStore = usageStore
        appDelegate.themeStore = themeStore
        appDelegate.settingsStore = settingsStore
        appDelegate.updateStore = updateStore
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}


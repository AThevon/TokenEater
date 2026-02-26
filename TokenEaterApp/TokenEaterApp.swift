import SwiftUI

@main
struct TokenEaterApp: App {
    private let usageStore = UsageStore()
    private let themeStore = ThemeStore()
    private let settingsStore = SettingsStore()
    private let updateStore = UpdateStore()

    private let statusBarController: StatusBarController

    init() {
        NotificationService().setupDelegate()
        statusBarController = StatusBarController(
            usageStore: usageStore,
            themeStore: themeStore,
            settingsStore: settingsStore,
            updateStore: updateStore
        )
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}


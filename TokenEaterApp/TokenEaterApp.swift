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
        WindowGroup(id: "settings") {
            RootView()
        }
        .environmentObject(usageStore)
        .environmentObject(themeStore)
        .environmentObject(settingsStore)
        .environmentObject(updateStore)
        .windowResizability(.contentSize)
    }
}

// MARK: - Root (routes onboarding vs settings — only observes settingsStore)

private struct RootView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        if settingsStore.hasCompletedOnboarding {
            SettingsContentView()
        } else {
            OnboardingView()
        }
    }
}

// MARK: - Settings Content (post-onboarding setup + update modal)

private struct SettingsContentView: View {
    @EnvironmentObject private var updateStore: UpdateStore
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        SettingsView()
            .sheet(isPresented: $updateStore.showUpdateModal) {
                UpdateModalView()
            }
            .task {
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
                themeStore.syncToSharedFile()
                updateStore.startAutoCheck()
            }
    }
}


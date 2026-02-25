import SwiftUI

@main
struct TokenEaterApp: App {
    private let usageStore = UsageStore()
    private let themeStore = ThemeStore()
    private let settingsStore = SettingsStore()
    private let updateStore = UpdateStore()

    @AppStorage("showMenuBar") private var showMenuBar = true

    init() {
        NotificationService().setupDelegate()
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

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPopoverView()
                .environmentObject(usageStore)
                .environmentObject(themeStore)
                .environmentObject(settingsStore)
                .environmentObject(updateStore)
        } label: {
            MenuBarLabel()
                .environmentObject(usageStore)
                .environmentObject(themeStore)
                .environmentObject(settingsStore)
        }
        .menuBarExtraStyle(.window)
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

// MARK: - Menu Bar Label

private struct MenuBarLabel: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Image(nsImage: rendered)
    }

    private var rendered: NSImage {
        MenuBarRenderer.render(MenuBarRenderer.RenderData(
            pinnedMetrics: settingsStore.pinnedMetrics,
            fiveHourPct: usageStore.fiveHourPct,
            sevenDayPct: usageStore.sevenDayPct,
            sonnetPct: usageStore.sonnetPct,
            pacingDelta: usageStore.pacingDelta,
            pacingZone: usageStore.pacingZone,
            pacingDisplayMode: settingsStore.pacingDisplayMode,
            hasConfig: usageStore.hasConfig,
            hasError: usageStore.hasError,
            themeColors: themeStore.current,
            thresholds: themeStore.thresholds,
            menuBarMonochrome: themeStore.menuBarMonochrome
        ))
    }
}

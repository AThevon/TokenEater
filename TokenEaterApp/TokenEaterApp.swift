import SwiftUI

@main
struct TokenEaterApp: App {
    @State private var usageStore = UsageStore()
    @State private var themeStore = ThemeStore()
    @State private var settingsStore = SettingsStore()

    init() {
        NotificationService().setupDelegate()
    }

    var body: some Scene {
        WindowGroup(id: "settings") {
            if settingsStore.hasCompletedOnboarding {
                SettingsView()
            } else {
                OnboardingView()
            }
        }
        .environment(usageStore)
        .environment(themeStore)
        .environment(settingsStore)
        .onChange(of: settingsStore.hasCompletedOnboarding) { _, completed in
            if completed {
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.reloadConfig(thresholds: themeStore.thresholds)
                usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
                themeStore.syncToSharedFile()
            }
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: Bindable(settingsStore).showMenuBar) {
            MenuBarPopoverView()
                .environment(usageStore)
                .environment(themeStore)
                .environment(settingsStore)
        } label: {
            Image(nsImage: menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarImage: NSImage {
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
            colorForPct: { themeStore.menuBarNSColor(for: $0) },
            colorForZone: { themeStore.menuBarPacingNSColor(for: $0) }
        ))
    }
}

import SwiftUI

@main
struct TokenEaterApp: App {
    @State private var usageStore = UsageStore()
    @State private var themeStore = ThemeStore()
    @State private var settingsStore = SettingsStore()
    @State private var updateStore = UpdateStore()

    init() {
        NotificationService().setupDelegate()
    }

    var body: some Scene {
        WindowGroup(id: "settings") {
            if settingsStore.hasCompletedOnboarding {
                SettingsView()
                    .sheet(isPresented: Bindable(updateStore).showUpdateModal) {
                        UpdateModalView()
                            .environment(updateStore)
                    }
                    .task {
                        updateStore.startAutoCheck()
                    }
            } else {
                OnboardingView()
            }
        }
        .environment(usageStore)
        .environment(themeStore)
        .environment(settingsStore)
        .environment(updateStore)
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
                .environment(updateStore)
        } label: {
            MenuBarLabel(
                usageStore: usageStore,
                themeStore: themeStore,
                settingsStore: settingsStore
            )
        }
        .menuBarExtraStyle(.window)
    }
}

/// Isolated view for the menu bar icon — keeps @Observable tracking
/// scoped here so usageStore/themeStore mutations never re-evaluate
/// the App body (which would needlessly re-evaluate the WindowGroup).
private struct MenuBarLabel: View {
    let usageStore: UsageStore
    let themeStore: ThemeStore
    let settingsStore: SettingsStore

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
            colorForPct: { themeStore.menuBarNSColor(for: $0) },
            colorForZone: { themeStore.menuBarPacingNSColor(for: $0) }
        ))
    }
}

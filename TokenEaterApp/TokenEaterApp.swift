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
        // FIX 6: SettingsContentView isolates Bindable(updateStore) from App.body
        WindowGroup(id: "settings") {
            if settingsStore.hasCompletedOnboarding {
                SettingsContentView()
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
                Task {
                    usageStore.proxyConfig = settingsStore.proxyConfig
                    usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
                    themeStore.syncToSharedFile()
                }
            }
        }
        .windowResizability(.contentSize)

        // FIX 2: MenuBarLabel uses @Environment — add .environment() on label:
        MenuBarExtra(isInserted: Bindable(settingsStore).showMenuBar) {
            MenuBarPopoverView()
                .environment(usageStore)
                .environment(themeStore)
                .environment(settingsStore)
                .environment(updateStore)
        } label: {
            MenuBarLabel()
                .environment(usageStore)
                .environment(themeStore)
                .environment(settingsStore)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - FIX 6: Isolates Bindable(updateStore) from App.body

private struct SettingsContentView: View {
    @Environment(UpdateStore.self) private var updateStore

    var body: some View {
        @Bindable var updateStore = updateStore
        SettingsView()
            .sheet(isPresented: $updateStore.showUpdateModal) {
                UpdateModalView()
            }
            .task {
                updateStore.startAutoCheck()
            }
    }
}

// MARK: - FIX 2: Menu Bar Label uses @Environment (proper observation scoping)

private struct MenuBarLabel: View {
    @Environment(UsageStore.self) private var usageStore
    @Environment(ThemeStore.self) private var themeStore
    @Environment(SettingsStore.self) private var settingsStore

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

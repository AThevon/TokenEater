import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var menuBarVM = MenuBarViewModel()
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        syncProxyConfig()
        ThemeManager.shared.syncToSharedContainer()
    }

    var body: some Scene {
        WindowGroup(id: "settings") {
            if hasCompletedOnboarding {
                SettingsView(onConfigSaved: { [weak menuBarVM] in
                    menuBarVM?.reloadConfig()
                    syncProxyConfig()
                })
            } else {
                OnboardingView()
            }
        }
        .onChange(of: hasCompletedOnboarding) { completed in
            if completed {
                menuBarVM.reloadConfig()
                syncProxyConfig()
            }
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPopoverView(viewModel: menuBarVM)
        } label: {
            Image(nsImage: menuBarVM.menuBarImage)
        }
        .menuBarExtraStyle(.window)
    }

    private func syncProxyConfig() {
        ClaudeAPIClient.shared.proxyConfig = ProxyConfig(
            enabled: UserDefaults.standard.bool(forKey: "proxyEnabled"),
            host: UserDefaults.standard.string(forKey: "proxyHost") ?? "127.0.0.1",
            port: {
                let port = UserDefaults.standard.integer(forKey: "proxyPort")
                return port > 0 ? port : 1080
            }()
        )
    }
}

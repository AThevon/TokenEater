import SwiftUI

struct MainAppView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var updateStore: UpdateStore

    @State private var selectedSection: AppSection = .dashboard

    private let panelBg = Color(red: 0.10, green: 0.10, blue: 0.12)

    var body: some View {
        if settingsStore.hasCompletedOnboarding {
            mainContent
        } else {
            onboardingContent
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        HStack(spacing: 4) {
            AppSidebar(selection: $selectedSection)

            Group {
                switch selectedSection {
                case .dashboard:
                    DashboardView()
                case .display:
                    DisplaySectionView()
                case .themes:
                    ThemesSectionView()
                case .settings:
                    SettingsSectionView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(panelBg))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(4)
        .task {
            usageStore.proxyConfig = settingsStore.proxyConfig
            usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
            themeStore.syncToSharedFile()
            updateStore.startAutoCheck()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { notification in
            if let section = notification.userInfo?["section"] as? String,
               let target = AppSection(rawValue: section) {
                selectedSection = target
            }
        }
    }

    // MARK: - Onboarding Content

    private var onboardingContent: some View {
        OnboardingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(panelBg))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(4)
            .frame(width: 680, height: 620)
    }
}

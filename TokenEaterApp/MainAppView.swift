import SwiftUI

struct MainAppView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var updateStore: UpdateStore
    @EnvironmentObject private var sessionStore: SessionStore

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
                    DisplaySectionView(initialMetrics: settingsStore.pinnedMetrics)
                case .themes:
                    ThemesSectionView(
                        initialWarning: themeStore.warningThreshold,
                        initialCritical: themeStore.criticalThreshold,
                        initialMargin: settingsStore.pacingMargin
                    )
                case .agentWatchers:
                    AgentWatchersSectionView()
                case .performance:
                    PerformanceSectionView()
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
            // Refresh on appear — throttled by UsageStore (10s debounce)
            await usageStore.refresh(thresholds: themeStore.thresholds)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { notification in
            if let section = notification.userInfo?["section"] as? String,
               let target = AppSection(rawValue: section) {
                selectedSection = target
            }
        }
        .sheet(isPresented: $updateStore.showUpdateModal) {
            UpdateModalView()
        }
    }

    // MARK: - Onboarding Content

    private var onboardingContent: some View {
        OnboardingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(panelBg))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(4)
            .frame(width: 680, height: 660)
    }
}

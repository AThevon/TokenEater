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
                    // DashboardView owns its own ScrollView (background gradient
                    // stays fixed, foreground content scrolls when it overflows).
                    DashboardView()
                case .display:
                    scrollingSection { DisplaySectionView(initialMetrics: settingsStore.pinnedMetrics) }
                case .themes:
                    scrollingSection {
                        ThemesSectionView(
                            initialWarning: themeStore.warningThreshold,
                            initialCritical: themeStore.criticalThreshold,
                            initialMargin: settingsStore.pacingMargin
                        )
                    }
                case .popover:
                    // PopoverSectionView owns its own scroll (the editor list)
                    // and needs full height for the split layout, so don't
                    // wrap it in scrollingSection.
                    PopoverSectionView()
                case .agentWatchers:
                    scrollingSection { AgentWatchersSectionView() }
                case .performance:
                    scrollingSection { PerformanceSectionView() }
                case .settings:
                    scrollingSection { SettingsSectionView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(panelBg))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .overlay {
            if updateStore.updateState.isModalVisible {
                UpdateModalView()
                    .transition(.opacity)
                    .animation(.spring(response: 0.4, dampingFraction: 0.9), value: updateStore.updateState.isModalVisible)
            }
        }
        .padding(4)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { notification in
            if let section = notification.userInfo?["section"] as? String,
               let target = AppSection(rawValue: section) {
                selectedSection = target
            }
        }
    }

    @ViewBuilder
    private func scrollingSection<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    // MARK: - Onboarding Content

    private var onboardingContent: some View {
        OnboardingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(panelBg))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(4)
            .frame(width: 700, height: 720)
    }
}

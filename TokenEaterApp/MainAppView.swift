import SwiftUI

struct MainAppView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var updateStore: UpdateStore
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var selectedSpace: AppSpace = .monitoring
    @State private var selectedSettingsSection: SettingsSection = .general

    var body: some View {
        if settingsStore.hasCompletedOnboarding {
            mainContent
        } else {
            onboardingContent
        }
    }

    // MARK: - Main

    private var mainContent: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack {
                TopPillsNav(selection: $selectedSpace)
                    .padding(.leading, DS.Spacing.xs)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(DS.Palette.glassFill)
                                .overlay(Circle().stroke(DS.Palette.glassBorderLo, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .help(String(localized: "menubar.quit"))
                .padding(.trailing, DS.Spacing.xs)
            }
            .padding(.top, DS.Spacing.xs)

            Group {
                switch selectedSpace {
                case .monitoring:
                    MonitoringView()
                case .history:
                    HistoryView()
                case .settings:
                    SettingsRootView(selection: $selectedSettingsSection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(selectedSpace)
            .transition(spaceTransition)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.sm)
        .dsWindowBackground()
        .overlay {
            if updateStore.updateState.isModalVisible {
                UpdateModalView()
                    .transition(.opacity)
                    .animation(DS.Motion.springSoft, value: updateStore.updateState.isModalVisible)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSection)) { notification in
            guard let payload = notification.userInfo?["section"] as? String,
                  let target = NavigationTarget.parse(payload) else { return }
            withAnimation(DS.Motion.springSnap) {
                selectedSpace = target.space
                if let sub = target.settingsSection {
                    selectedSettingsSection = sub
                }
            }
        }
    }

    /// Cross-fade depth-shift -> entry pops in from a slightly compressed scale
    /// (0.97 -> 1.0), exit drifts out at a slightly expanded scale (1.0 -> 1.03).
    /// No directional movement -> the eye stays on the same axis, only the
    /// "depth" of the layer shifts, à la Arc tab switch + native macOS window
    /// fades. Stylé sans donner mal au crâne.
    private var spaceTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 1.03, anchor: .center))
        )
    }

    // MARK: - Onboarding

    private var onboardingContent: some View {
        OnboardingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.modal)
                    .fill(DS.Palette.bgElevated)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.modal))
            .padding(4)
            .frame(width: 700, height: 720)
    }
}

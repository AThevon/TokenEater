import SwiftUI

struct MainAppView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var updateStore: UpdateStore
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var selectedSpace: AppSpace = .monitoring
    @State private var selectedSettingsSection: SettingsSection = .general
    @State private var powerHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Blur burst transition between spaces. `displayedSpace` lags
    // `selectedSpace` until the blur peak, where the content swap fires
    // inside `withTransaction(animation: nil)` so the swap is invisible
    // under the full blur (no implicit crossfade).
    @State private var displayedSpace: AppSpace = .monitoring
    @State private var transitionBlur: CGFloat = 0
    @State private var isTransitioningSpace = false

    // Hoisted from the child views so each store's cache outlives the
    // navigation-driven view destruction; re-entering a space hits warm
    // data instead of triggering a fresh load.
    @StateObject private var historyStore = HistoryStore()
    @StateObject private var insightsStore = MonitoringInsightsStore()

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
                        .foregroundStyle(powerHovering ? DS.Palette.semanticError : DS.Palette.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(powerHovering
                                      ? DS.Palette.semanticError.opacity(0.18)
                                      : DS.Palette.glassFill)
                                .overlay(
                                    Circle().stroke(
                                        powerHovering
                                            ? DS.Palette.semanticError.opacity(0.55)
                                            : DS.Palette.glassBorderLo,
                                        lineWidth: 1
                                    )
                                )
                        )
                        .shadow(color: powerHovering ? DS.Palette.semanticError.opacity(0.55) : .clear,
                                radius: powerHovering ? 8 : 0)
                        .scaleEffect(powerHovering && !reduceMotion ? 1.05 : 1.0)
                }
                .buttonStyle(.plain)
                .help(String(localized: "menubar.quit"))
                .padding(.trailing, DS.Spacing.xs)
                .onHover { hovering in
                    withAnimation(DS.Motion.springSnap) { powerHovering = hovering }
                }
            }
            .padding(.top, DS.Spacing.xs)

            Group {
                switch displayedSpace {
                case .monitoring:
                    MonitoringView(insightsStore: insightsStore)
                case .history:
                    HistoryView(store: historyStore)
                case .settings:
                    SettingsRootView(selection: $selectedSettingsSection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(displayedSpace)
            .blur(radius: reduceMotion ? 0 : transitionBlur)
            .opacity(reduceMotion ? max(0, 1 - transitionBlur) : 1)
            // Safety net: ensure no implicit animation runs on the
            // `displayedSpace` swap (the flip is also wrapped in
            // `withTransaction(animation: nil)` upstream).
            .animation(nil, value: displayedSpace)
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
            // No `withAnimation` wrap - the blur burst is driven by
            // `onChange(of: selectedSpace)` with its own contexts.
            selectedSpace = target.space
            if let sub = target.settingsSection {
                withAnimation(DS.Motion.springSnap) {
                    selectedSettingsSection = sub
                }
            }
        }
        .onChange(of: selectedSpace) { _, newSpace in
            performSpaceTransition(to: newSpace)
        }
    }

    // MARK: - Blur burst transition between spaces

    /// Drives the inter-space transition: easeIn ramp-up to peak blur,
    /// instant content swap (no implicit animation) while fully blurred,
    /// then easeOut ramp-down. Reduce-motion bypasses blur and fades the
    /// surface via opacity derived from the same `transitionBlur` ramp.
    private func performSpaceTransition(to newSpace: AppSpace) {
        guard newSpace != displayedSpace else { return }

        // Ignore rapid clicks during a transition; the current run
        // completes against the latest `selectedSpace`.
        if isTransitioningSpace { return }
        isTransitioningSpace = true

        let rampUp: Double = reduceMotion ? 0.09 : 0.16
        let rampDown: Double = reduceMotion ? 0.09 : 0.24
        let blurPeak: CGFloat = 5

        withAnimation(.easeIn(duration: rampUp)) {
            transitionBlur = blurPeak
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + rampUp) {
            withTransaction(Transaction(animation: nil)) {
                self.displayedSpace = newSpace
            }

            withAnimation(.easeOut(duration: rampDown)) {
                self.transitionBlur = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + rampDown) {
                self.isTransitioningSpace = false
            }
        }
    }

    // MARK: - Onboarding

    private var onboardingContent: some View {
        OnboardingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Palette.bgElevated)
    }
}

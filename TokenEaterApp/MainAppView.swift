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

    // Directional blur burst transition between spaces.
    // `displayedSpace` lags `selectedSpace` until the blur peak, where the
    // content swap fires inside a `withTransaction(animation: nil)` so it
    // lands instantly under cover of full blur. Without that guard, the
    // outer pill-nav `withAnimation` context would crossfade the swap and
    // we'd see "blur in, blur out, snap content" instead of "blur in,
    // swap at peak, blur out."
    @State private var displayedSpace: AppSpace = .monitoring
    @State private var transitionBlur: CGFloat = 0
    @State private var isTransitioningSpace = false

    // Hoisted from the child views so the data outlives the
    // navigation-driven view destruction. Without this, switching away
    // from History tore down `HistoryStore` along with its loaded buckets,
    // and the next return to History showed empty placeholders for the
    // ~100ms it took the async reload to finish - the values "popped in"
    // a quart de seconde after the blur burst resolved. Now the stores
    // live at the MainAppView level and re-entries hit warm data.
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
            // Critical: tells SwiftUI that no implicit animation should run
            // when `displayedSpace` flips. The flip itself is wrapped in
            // `withTransaction(animation: nil)`, but this is the second
            // safety net at the receiving end.
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
            // Don't wrap `selectedSpace` in withAnimation - the directional
            // blur burst is driven by `onChange(of: selectedSpace)` and
            // manages its own animation contexts. Wrapping here would push
            // an outer animation into the swap and reintroduce the crossfade.
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

    /// Mirrors the flip-card pattern from `MonitoringView` -> `easeIn`
    /// ramp-up to peak blur, instant content swap inside a
    /// `Transaction(animation: nil)` while the surface is fully blurred
    /// (so the swap is invisible to the eye), then `easeOut` ramp-down
    /// to rest.
    ///
    /// Reduce-motion: blur is bypassed; the surface fades via opacity
    /// derived from the same `transitionBlur` ramp so the state machine
    /// stays unified across both modes.
    private func performSpaceTransition(to newSpace: AppSpace) {
        guard newSpace != displayedSpace else { return }

        // Bail mid-flight: rapid pill clicks during a 0.40s transition
        // shouldn't pile up. The current animation completes against the
        // latest `selectedSpace`, the next click is honored once idle.
        if isTransitioningSpace { return }
        isTransitioningSpace = true

        let rampUp: Double = reduceMotion ? 0.09 : 0.16
        let rampDown: Double = reduceMotion ? 0.09 : 0.24
        let blurPeak: CGFloat = 5

        // Phase 1 - ramp-up: outgoing page blurs to peak. easeIn so the
        // dwell at peak feels brief.
        withAnimation(.easeIn(duration: rampUp)) {
            transitionBlur = blurPeak
        }

        // Phase 2 - swap at peak: content flip lands UNDER the full blur
        // (invisible).
        DispatchQueue.main.asyncAfter(deadline: .now() + rampUp) {
            withTransaction(Transaction(animation: nil)) {
                self.displayedSpace = newSpace
            }

            // Phase 3 - ramp-down: incoming page resolves to crisp.
            // easeOut so the arrival decelerates and feels grounded.
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

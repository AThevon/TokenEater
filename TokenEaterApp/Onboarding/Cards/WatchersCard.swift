import SwiftUI

/// Third card - optional, default ON. Reuses the real `SessionTraitView`
/// with mocked `ClaudeSession`s + `proximity = 1.0` so the preview is
/// pixel-identical to the live overlay rendering. Toggling off desaturates
/// the tiles in place.
struct WatchersCard: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var settingsStore: SettingsStore

    private let accent = DS.Palette.accentHistory // blue, info-coloured

    var body: some View {
        OnboardingCard(
            kind: .optional,
            tilt: .right,
            title: "onboarding.card.watchers.title",
            statusText: statusText,
            statusColor: statusColor,
            accent: accent,
            scene: { scene },
            control: { control }
        )
        // The viewModel owns its own private SettingsStore (created in init
        // because env objects aren't reachable from @StateObject init). To
        // keep the actual app-wide overlay in sync, this card writes to the
        // live env SettingsStore on toggle and mirrors back to the viewModel
        // so progress / readyCount stay accurate. Without this, flipping
        // off in onboarding would silently fail to disable the live overlay.
        .onAppear { viewModel.watcherEnabled = settingsStore.overlayEnabled }
        .onChange(of: settingsStore.overlayEnabled) { _, newValue in
            viewModel.watcherEnabled = newValue
        }
    }

    private var scene: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(mockSessions) { session in
                SessionTraitView(session: session, proximity: 1.0, scale: 0.92)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(settingsStore.overlayEnabled ? 1 : 0.42)
        .saturation(settingsStore.overlayEnabled ? 1 : 0.5)
    }

    private var control: some View {
        Toggle("", isOn: Binding(
            get: { settingsStore.overlayEnabled },
            set: { settingsStore.overlayEnabled = $0 }
        ))
        .toggleStyle(SwitchToggleStyle(tint: DS.Palette.brandPrimary))
        .controlSize(.mini)
        .labelsHidden()
    }

    private var statusText: LocalizedStringResource {
        settingsStore.overlayEnabled
            ? "onboarding.card.watchers.status.on"
            : "onboarding.card.watchers.status.off"
    }

    private var statusColor: Color {
        settingsStore.overlayEnabled ? DS.Palette.brandPrimary : Color.white.opacity(0.3)
    }

    /// Computed (not static) so each render gets fresh `lastUpdate` /
    /// `startedAt` dates - keeps the tiles rendering as "live" rather
    /// than going stale after a few seconds (SessionTraitView checks
    /// freshness for background opacity).
    private var mockSessions: [ClaudeSession] {
        let now = Date()
        return [
            ClaudeSession(
                id: "onboarding-mock-1",
                projectPath: "/Users/dev/tokeneater",
                gitBranch: "feat/menu-bar",
                model: "claude-sonnet-4-6",
                state: .thinking,
                lastUpdate: now,
                startedAt: now.addingTimeInterval(-300),
                processPid: 1,
                sourceKind: .unknown,
                contextTokens: 70_000,
                contextMax: 200_000
            ),
            ClaudeSession(
                id: "onboarding-mock-2",
                projectPath: "/Users/dev/linear-clone",
                gitBranch: "feat/auth",
                model: "claude-sonnet-4-6",
                state: .toolExec,
                lastUpdate: now,
                startedAt: now.addingTimeInterval(-180),
                processPid: 2,
                sourceKind: .unknown,
                contextTokens: 124_000,
                contextMax: 200_000
            ),
            ClaudeSession(
                id: "onboarding-mock-3",
                projectPath: "/Users/dev/api-gateway",
                gitBranch: "hotfix",
                model: "claude-sonnet-4-6",
                state: .idle,
                lastUpdate: now,
                startedAt: now.addingTimeInterval(-60),
                processPid: 3,
                sourceKind: .unknown,
                contextTokens: 96_000,
                contextMax: 200_000
            ),
        ]
    }
}

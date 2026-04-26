import SwiftUI

/// Third card - optional, default ON. The scene reuses real `WatcherTilePreview`
/// components so the user sees exactly the chrome they'll get in the live
/// overlay. Toggling off desaturates the preview tiles in place.
struct WatchersCard: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var settingsStore: SettingsStore

    private let accent = Color(red: 0.30, green: 0.81, blue: 0.50) // green

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
    }

    private var scene: some View {
        VStack(spacing: 5) {
            WatcherTilePreview(
                style: settingsStore.watcherStyle,
                project: "tokeneater",
                branch: "main",
                percentage: viewModel.watcherEnabled ? 35 : 0,
                statusColor: Color(red: 0.29, green: 0.87, blue: 0.50)
            )
            WatcherTilePreview(
                style: settingsStore.watcherStyle,
                project: "linear-clone",
                branch: "feat/auth",
                percentage: viewModel.watcherEnabled ? 62 : 0,
                statusColor: Color(red: 1.0, green: 0.62, blue: 0.04)
            )
            WatcherTilePreview(
                style: settingsStore.watcherStyle,
                project: "api-gateway",
                branch: "hotfix",
                percentage: viewModel.watcherEnabled ? 48 : 0,
                statusColor: Color(red: 0.23, green: 0.51, blue: 0.96)
            )
        }
        .padding(9)
        .opacity(viewModel.watcherEnabled ? 1 : 0.42)
        .saturation(viewModel.watcherEnabled ? 1 : 0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var control: some View {
        Toggle("", isOn: Binding(
            get: { viewModel.watcherEnabled },
            set: { viewModel.setWatcherEnabled($0) }
        ))
        .toggleStyle(SwitchToggleStyle(tint: accent))
        .controlSize(.mini)
        .labelsHidden()
    }

    private var statusText: LocalizedStringResource {
        viewModel.watcherEnabled
            ? "onboarding.card.watchers.status.on"
            : "onboarding.card.watchers.status.off"
    }

    private var statusColor: Color {
        viewModel.watcherEnabled ? accent : Color.white.opacity(0.3)
    }
}

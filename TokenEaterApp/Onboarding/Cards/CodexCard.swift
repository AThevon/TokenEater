import SwiftUI

struct CodexCard: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        OnboardingCard(
            kind: .optional,
            tilt: .left,
            title: "onboarding.card.codex.title",
            statusText: statusText,
            statusColor: isReady ? .green : .secondary,
            accent: .green,
            scene: {
                HStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 24))
                        .foregroundStyle(.green)
                    Text("onboarding.card.codex.description")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(String(localized: "settings.redetect")) { viewModel.checkCodex() }
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 14)
            },
            control: {
                Toggle(String(localized: "onboarding.card.codex.track"), isOn: $settingsStore.codexEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
        )
        .onAppear {
            viewModel.checkCodex()
            viewModel.codexEnabled = settingsStore.codexEnabled
        }
        .onChange(of: settingsStore.codexEnabled) { _, enabled in
            viewModel.codexEnabled = enabled
        }
    }

    private var isReady: Bool {
        settingsStore.codexEnabled && viewModel.codexStatus.isTrackable && !viewModel.codexStatus.isExpired()
    }

    private var statusText: LocalizedStringResource {
        if viewModel.codexStatus.isExpired() { return "codex.status.expired" }
        switch viewModel.codexStatus {
        case .notInstalled: return "codex.status.notInstalled"
        case .noCredentials: return "codex.status.noCredentials"
        case .apiKeyOnly: return "codex.status.apiKey"
        case .chatgpt: return settingsStore.codexEnabled ? "codex.status.connected" : "codex.tracking.off"
        }
    }
}

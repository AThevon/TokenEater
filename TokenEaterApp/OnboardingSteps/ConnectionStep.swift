import SwiftUI

struct ConnectionStep: View {
    @Bindable var viewModel: OnboardingViewModel
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            switch viewModel.connectionStatus {
            case .idle:
                primingContent
            case .connecting:
                connectingContent
            case .success(let usage):
                successContent(usage: usage)
            case .failed(let message):
                failedContent(message: message)
            }

            Spacer()

            // Navigation
            bottomBar
        }
        .padding(32)
    }

    // MARK: - Priming (before connection)

    private var primingContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("onboarding.connection.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Text("onboarding.connection.simple")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Button {
                viewModel.connect()
            } label: {
                Label("onboarding.connection.authorize", systemImage: "key.fill")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
    }

    // MARK: - Connecting

    private var connectingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("onboarding.connection.connecting")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Success

    private func successContent(usage: UsageResponse) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("onboarding.connection.success.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            // Real data preview
            realDataPreview(usage: usage)

            // Widget hint
            Label {
                Text("onboarding.connection.widget.hint")
                    .font(.system(size: 12))
            } icon: {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.blue)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
        }
    }

    private func realDataPreview(usage: UsageResponse) -> some View {
        let values: [(String, Int, Color)] = [
            ("5h", Int(usage.fiveHour?.utilization ?? 0), Color(hex: "#22C55E")),
            ("7d", Int(usage.sevenDay?.utilization ?? 0), Color(hex: "#FF9F0A")),
            ("Sonnet", Int(usage.sevenDaySonnet?.utilization ?? 0), Color(hex: "#3B82F6")),
        ]

        return HStack(spacing: 24) {
            ForEach(values, id: \.0) { label, value, color in
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(color.opacity(0.15), lineWidth: 6)
                            .frame(width: 56, height: 56)
                        Circle()
                            .trim(from: 0, to: CGFloat(value) / 100)
                            .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                        Text("\(value)%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Failed

    private func failedContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("onboarding.connection.failed.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            // Tip about re-login
            Label {
                Text("onboarding.connection.failed.tip")
                    .font(.system(size: 12))
            } icon: {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)

            Button {
                viewModel.connectionStatus = .idle
            } label: {
                Label("onboarding.connection.retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        switch viewModel.connectionStatus {
        case .success:
            Button {
                viewModel.completeOnboarding()
                settingsStore.hasCompletedOnboarding = true
            } label: {
                Text("onboarding.connection.start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        default:
            HStack {
                Button {
                    viewModel.goBack()
                } label: {
                    Text("onboarding.back")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()
            }
        }
    }
}

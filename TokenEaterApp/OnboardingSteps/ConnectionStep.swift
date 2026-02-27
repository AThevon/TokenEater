import SwiftUI

struct ConnectionStep: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var settingsStore: SettingsStore

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
            bottomBar
        }
        .padding(32)
    }

    // MARK: - Priming

    private var primingContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            GlowText(
                String(localized: "onboarding.connection.title"),
                font: .system(size: 18, weight: .semibold, design: .rounded),
                color: .white,
                glowRadius: 4
            )

            Text("onboarding.connection.simple")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            darkPrimaryButton("onboarding.connection.authorize") { viewModel.connect() }
                .padding(.top, 8)
        }
    }

    // MARK: - Connecting

    private var connectingContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)
            Text("onboarding.connection.connecting")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Success

    private func successContent(usage: UsageResponse) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            GlowText(
                String(localized: "onboarding.connection.success.title"),
                font: .system(size: 18, weight: .semibold, design: .rounded),
                color: .white,
                glowRadius: 4
            )

            realDataPreview(usage: usage)

            Label {
                Text("onboarding.connection.widget.hint")
                    .font(.system(size: 12))
            } icon: {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.blue)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.white.opacity(0.5))
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
                        RingGauge(
                            percentage: value,
                            gradient: LinearGradient(colors: [color], startPoint: .leading, endPoint: .trailing),
                            size: 56,
                            glowColor: color,
                            glowRadius: 3
                        )
                        GlowText(
                            "\(value)%",
                            font: .system(size: 12, weight: .bold, design: .rounded),
                            color: color,
                            glowRadius: 2
                        )
                    }
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial.opacity(0.15))
        )
    }

    // MARK: - Failed

    private func failedContent(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            GlowText(
                String(localized: "onboarding.connection.failed.title"),
                font: .system(size: 18, weight: .semibold, design: .rounded),
                color: .white,
                glowRadius: 4
            )

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Label {
                Text("onboarding.connection.failed.tip")
                    .font(.system(size: 12))
            } icon: {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 11))
            }
            .foregroundStyle(.white.opacity(0.5))

            darkButton("onboarding.connection.retry") { viewModel.connectionStatus = .idle }
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        switch viewModel.connectionStatus {
        case .success:
            darkPrimaryButton("onboarding.connection.start") {
                viewModel.completeOnboarding()
                settingsStore.hasCompletedOnboarding = true
            }
        default:
            HStack {
                darkButton("onboarding.back") { viewModel.goBack() }
                Spacer()
            }
        }
    }
}

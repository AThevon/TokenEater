import SwiftUI

/// First card - gates the onboarding. Auto-checks for the `claude` CLI on
/// appear; renders the appropriate scene (terminal preview / install guide
/// / spinner) and exposes a Retry button when not found.
struct ClaudeCodeCard: View {
    @ObservedObject var viewModel: OnboardingViewModel

    private let accent = Color(red: 0.30, green: 0.81, blue: 0.50) // green

    var body: some View {
        OnboardingCard(
            kind: .required,
            tilt: .left,
            title: "onboarding.card.claudecode.title",
            statusText: statusText,
            statusColor: statusColor,
            accent: accent,
            scene: { scene },
            control: { control }
        )
        .onAppear { viewModel.checkClaudeCode() }
    }

    @ViewBuilder
    private var scene: some View {
        switch viewModel.claudeCodeStatus {
        case .checking:
            VStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("onboarding.card.claudecode.checking")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .detected:
            terminalPreview
                .padding(10)

        case .notFound:
            installGuide
                .padding(10)
        }
    }

    private var terminalPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 7, height: 7)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 7, height: 7)
                Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: 7, height: 7)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.025))
            .overlay(
                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1),
                alignment: .bottom
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("~/proj").foregroundStyle(accent)
                    Text("$").foregroundStyle(.white.opacity(0.4))
                    Text("claude --version").foregroundStyle(.white)
                }
                Text("claude code 2.0.4").foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 4) {
                    Text("\u{2713} ready").foregroundStyle(accent)
                }
                HStack(spacing: 4) {
                    Text("~/proj").foregroundStyle(accent)
                    Text("$").foregroundStyle(.white.opacity(0.4))
                    BlinkingCursor(color: accent)
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 0.02, green: 0.03, blue: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var installGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepRow(1, key: "onboarding.card.claudecode.notfound.step1")
            stepRow(2, key: "onboarding.card.claudecode.notfound.step2")
            stepRow(3, key: "onboarding.card.claudecode.notfound.step3")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func stepRow(_ n: Int, key: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("\(n)")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.29))
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color(red: 1.0, green: 0.62, blue: 0.04).opacity(0.18)))
            Text(key)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var control: some View {
        if viewModel.claudeCodeStatus == .notFound {
            Button {
                viewModel.checkClaudeCode()
            } label: {
                Text("onboarding.card.claudecode.retry")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
        } else {
            EmptyView()
        }
    }

    private var statusText: LocalizedStringResource {
        switch viewModel.claudeCodeStatus {
        case .checking: return "onboarding.card.claudecode.status.checking"
        case .detected: return "onboarding.card.claudecode.status.detected"
        case .notFound: return "onboarding.card.claudecode.status.notfound"
        }
    }

    private var statusColor: Color {
        switch viewModel.claudeCodeStatus {
        case .checking: return Color.white.opacity(0.3)
        case .detected: return accent
        case .notFound: return Color(red: 1.0, green: 0.62, blue: 0.04)
        }
    }
}

/// Terminal cursor that blinks via on/off opacity. Pulled out so the
/// terminal preview stays declarative.
private struct BlinkingCursor: View {
    let color: Color
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 4, height: 9)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

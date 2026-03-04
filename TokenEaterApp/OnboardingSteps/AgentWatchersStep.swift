import SwiftUI

struct AgentWatchersStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    @State private var tmuxCopied = false

    private let tmuxLine = "set-option -g update-environment \"TERM_PROGRAM\""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "eye.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            GlowText(
                String(localized: "onboarding.watchers.title"),
                font: .system(size: 18, weight: .semibold, design: .rounded),
                color: .white,
                glowRadius: 4
            )

            Text("onboarding.watchers.description")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            // Status legend (2×3 grid)
            VStack(spacing: 8) {
                HStack(spacing: 20) {
                    legendDot(color: Color(red: 0.3, green: 0.78, blue: 0.52), label: "idle")
                    legendDot(color: Color(red: 0.95, green: 0.62, blue: 0.22), label: "thinking")
                    legendDot(color: Color(red: 0.38, green: 0.58, blue: 0.95), label: "executing")
                }
                HStack(spacing: 20) {
                    legendDot(color: Color(red: 0.7, green: 0.45, blue: 0.95), label: "waiting")
                    legendDot(color: Color(red: 0.25, green: 0.85, blue: 0.85), label: "subagent")
                    legendDot(color: Color(red: 0.55, green: 0.55, blue: 0.60), label: "compacting")
                }

                Text("onboarding.watchers.settings.hint")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)

                Text("onboarding.performance.hint")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
            }

            // tmux hint
            VStack(spacing: 8) {
                Text("onboarding.watchers.tmux.hint")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)

                HStack(spacing: 8) {
                    Text(tmuxLine)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.black.opacity(0.3))
                        )

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tmuxLine, forType: .string)
                        tmuxCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            tmuxCopied = false
                        }
                    } label: {
                        Image(systemName: tmuxCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 380)
            }

            Spacer()

            // Navigation
            HStack {
                darkButton("onboarding.back") { viewModel.goBack() }
                Spacer()
                darkPrimaryButton("onboarding.continue") { viewModel.goNext() }
            }
        }
        .padding(32)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

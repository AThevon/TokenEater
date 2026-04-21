import SwiftUI

struct AgentWatchersStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 22) {
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
                .frame(maxWidth: 420)

            statusLegend

            terminalCompatibilityCard

            Text("onboarding.performance.hint")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)

            Spacer()

            HStack {
                darkButton("onboarding.back") { viewModel.goBack() }
                Spacer()
                darkPrimaryButton("onboarding.continue") { viewModel.goNext() }
            }
        }
        .padding(32)
    }

    // MARK: - Status legend

    private var statusLegend: some View {
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
        }
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

    // MARK: - Terminal compatibility card

    /// Replaces the old inline tmux / Kitty config snippets. Most terminals work
    /// out of the box; tmux, Kitty, and WezTerm each need a one-line config
    /// tweak that lives in Settings → Watchers and docs, not in onboarding.
    private var terminalCompatibilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
                Text(String(localized: "onboarding.watchers.compat.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            // Terminal pills — each pill represents a terminal TokenEater can
            // click-teleport into without any user-side configuration.
            HStack(spacing: 6) {
                terminalPill("iTerm2")
                terminalPill("Terminal.app")
                terminalPill("Warp")
                terminalPill("Ghostty")
                terminalPill("Alacritty")
                terminalPill("VS Code")
                terminalPill("Cursor")
            }

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 2)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 1)
                Text(String(localized: "onboarding.watchers.compat.advanced"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func terminalPill(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            )
    }
}

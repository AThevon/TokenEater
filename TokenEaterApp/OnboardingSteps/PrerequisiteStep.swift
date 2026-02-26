import SwiftUI

struct PrerequisiteStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            statusIcon
            statusContent
            Spacer()

            // Navigation
            HStack {
                darkButton("onboarding.back") { viewModel.goBack() }
                Spacer()
                darkPrimaryButton("onboarding.continue") { viewModel.goNext() }
                    .disabled(viewModel.claudeCodeStatus != .detected)
                    .opacity(viewModel.claudeCodeStatus != .detected ? 0.4 : 1.0)
            }
        }
        .padding(32)
        .onAppear { viewModel.checkClaudeCode() }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.claudeCodeStatus {
        case .checking:
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white)
        case .detected:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
        case .notFound:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch viewModel.claudeCodeStatus {
        case .checking:
            Text("onboarding.prereq.checking")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.6))
        case .detected:
            detectedContent
        case .notFound:
            notFoundContent
        }
    }

    private var detectedContent: some View {
        VStack(spacing: 12) {
            GlowText(
                String(localized: "onboarding.prereq.detected.title"),
                font: .system(size: 18, weight: .semibold, design: .rounded),
                color: .white,
                glowRadius: 4
            )
            Text("onboarding.prereq.detected.simple")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            planRequirement
        }
    }

    private var notFoundContent: some View {
        VStack(spacing: 16) {
            GlowText(
                String(localized: "onboarding.prereq.notfound.title"),
                font: .system(size: 18, weight: .semibold, design: .rounded),
                color: .white,
                glowRadius: 4
            )
            VStack(alignment: .leading, spacing: 12) {
                guideStep(number: 1, text: String(localized: "onboarding.prereq.step1"))
                guideStep(number: 2, text: String(localized: "onboarding.prereq.step2"))
                guideStep(number: 3, text: String(localized: "onboarding.prereq.step3"))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial.opacity(0.15))
            )
            HStack(spacing: 12) {
                Link(destination: URL(string: "https://docs.anthropic.com/en/docs/claude-code/overview")!) {
                    Label("onboarding.prereq.install.link", systemImage: "arrow.up.right")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                }
                darkButton("onboarding.prereq.retry") { viewModel.checkClaudeCode() }
            }
            planRequirement
        }
    }

    private var planRequirement: some View {
        Label {
            Text("onboarding.prereq.plan.required")
                .font(.system(size: 12))
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 11))
        }
        .foregroundStyle(.white.opacity(0.5))
        .padding(.top, 4)
    }

    private func guideStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.blue)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

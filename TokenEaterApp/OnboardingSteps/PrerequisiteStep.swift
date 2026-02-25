import SwiftUI

struct PrerequisiteStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Status icon
            statusIcon

            // Content adapted to detection status
            statusContent

            Spacer()

            // Navigation
            HStack {
                Button {
                    viewModel.goBack()
                } label: {
                    Text("onboarding.back")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()

                Button {
                    viewModel.goNext()
                } label: {
                    Text("onboarding.continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.claudeCodeStatus != .detected)
            }
        }
        .padding(32)
        .onAppear {
            viewModel.checkClaudeCode()
        }
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        switch viewModel.claudeCodeStatus {
        case .checking:
            ProgressView()
                .controlSize(.large)
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

    // MARK: - Status Content

    @ViewBuilder
    private var statusContent: some View {
        switch viewModel.claudeCodeStatus {
        case .checking:
            Text("onboarding.prereq.checking")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

        case .detected:
            detectedContent

        case .notFound:
            notFoundContent
        }
    }

    private var detectedContent: some View {
        VStack(spacing: 12) {
            Text("onboarding.prereq.detected.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Text("onboarding.prereq.detected.simple")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            planRequirement
        }
    }

    private var notFoundContent: some View {
        VStack(spacing: 16) {
            Text("onboarding.prereq.notfound.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            // Install guide
            VStack(alignment: .leading, spacing: 12) {
                guideStep(number: 1, text: String(localized: "onboarding.prereq.step1"))
                guideStep(number: 2, text: String(localized: "onboarding.prereq.step2"))
                guideStep(number: 3, text: String(localized: "onboarding.prereq.step3"))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )

            HStack(spacing: 12) {
                Link(destination: URL(string: "https://docs.anthropic.com/en/docs/claude-code/overview")!) {
                    Label("onboarding.prereq.install.link", systemImage: "arrow.up.right")
                }

                Button {
                    viewModel.checkClaudeCode()
                } label: {
                    Label("onboarding.prereq.retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
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
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private func guideStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
    }
}

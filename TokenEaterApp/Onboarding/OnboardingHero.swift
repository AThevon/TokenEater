import SwiftUI

/// Right column of the onboarding. Static copy + a progress indicator + the
/// Finish CTA at the bottom-right. Title and subtitle are left-aligned in
/// reading flow; the progress + Finish anchor to the trailing edge so the
/// CTA sits naturally bottom-right of the page.
/// Finish is disabled until both gates (Claude Code + Connect) are green.
struct OnboardingHero: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var settingsStore: SettingsStore

    private let accent = DS.Palette.brandPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("onboarding.hero.label")
                .font(.system(size: 10))
                .tracking(2.0)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.bottom, 4)

            heroTitle

            Spacer(minLength: 0)

            HStack {
                Spacer()
                progressBar
            }
            HStack {
                Spacer()
                finishButton
            }
        }
        .padding(.top, 4)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var heroTitle: some View {
        Text("onboarding.hero.title")
            .font(.system(size: 30, weight: .bold))
            .tracking(-0.5)
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, .white.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var progressBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                ForEach(0..<viewModel.totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i < viewModel.readyCount ? Color(red: 0.30, green: 0.81, blue: 0.50) : Color.white.opacity(0.12))
                        .frame(width: 6, height: 6)
                        .shadow(color: i < viewModel.readyCount
                                ? Color(red: 0.30, green: 0.81, blue: 0.50).opacity(0.7)
                                : .clear,
                                radius: 4)
                        .animation(DS.Motion.springSnap, value: viewModel.readyCount)
                }
            }
            Text("onboarding.progress.label \(viewModel.readyCount) \(viewModel.totalSteps)")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .monospacedDigit()
        }
    }

    private var finishButton: some View {
        Button {
            viewModel.completeOnboarding()
            settingsStore.hasCompletedOnboarding = true
        } label: {
            Text("onboarding.finish")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(finishBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(viewModel.canFinish ? 0.18 : 0.04), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(
                    color: viewModel.canFinish ? accent.opacity(0.5) : .clear,
                    radius: 14
                )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canFinish)
        .opacity(viewModel.canFinish ? 1 : 0.55)
        .animation(DS.Motion.springSnap, value: viewModel.canFinish)
    }

    @ViewBuilder
    private var finishBackground: some View {
        if viewModel.canFinish {
            LinearGradient(
                colors: [DS.Palette.brandPrimary, DS.Palette.brandPressed],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            Color.white.opacity(0.06)
        }
    }
}

import SwiftUI

/// Single-page onboarding. Brand header + body split: left = hero with
/// progress + finish, right = 2x2 grid of cards. The four cards each own
/// a state machine that talks to `OnboardingViewModel`.
///
/// The chrome (rounded background, modal radius) is provided by the parent
/// `MainAppView.onboardingContent`; this view stays transparent on top.
struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 16) {
            brandBar
            bodyContent
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var brandBar: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text("TokenEater")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Spacer()
        }
    }

    private var bodyContent: some View {
        HStack(alignment: .top, spacing: 22) {
            OnboardingHero(viewModel: viewModel)
                .frame(width: 280)

            cardsGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var cardsGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                ClaudeCodeCard(viewModel: viewModel)
                NotificationsCard(viewModel: viewModel)
            }
            GridRow {
                WatchersCard(viewModel: viewModel)
                ConnectCard(viewModel: viewModel)
            }
        }
    }
}

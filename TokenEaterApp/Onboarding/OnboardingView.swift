import SwiftUI

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
            cardsGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            OnboardingHero(viewModel: viewModel)
                .frame(width: 280)
        }
    }

    /// Two questions, one row each.
    ///
    /// Which providers you use, then what the app does with them. That split
    /// only works if each provider's whole setup lives on its own card, which
    /// is why authorizing the Keychain moved out of the second row: it is
    /// Claude's setup, not a behaviour of the app, and having it down there
    /// gave Claude two cards to OpenAI's one before a word had been read.
    private var cardsGrid: some View {
        VStack(spacing: 12) {
            groupLabel("onboarding.providers.heading", aside: "onboarding.providers.rule")

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    ProviderSetupCard(provider: .claude, viewModel: viewModel)
                    ProviderSetupCard(provider: .codex, viewModel: viewModel)
                }
            }

            groupLabel("onboarding.app.heading", aside: nil)
                .padding(.top, 2)

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    NotificationsCard(viewModel: viewModel)
                    WatchersCard(viewModel: viewModel)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func groupLabel(_ key: LocalizedStringResource, aside: LocalizedStringResource?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .font(DS.Typography.micro)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(DS.Palette.textTertiary)
            if let aside {
                Text(aside)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.22))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

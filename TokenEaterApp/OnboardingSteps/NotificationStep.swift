import SwiftUI

struct NotificationStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            GlowText(
                String(localized: "onboarding.notif.title"),
                font: .system(size: 18, weight: .semibold, design: .rounded),
                color: .white,
                glowRadius: 4
            )

            Text("onboarding.notif.simple")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            notificationMockup
            actionArea

            Spacer()

            // Navigation
            HStack(alignment: .top) {
                darkButton("onboarding.back") { viewModel.goBack() }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    darkPrimaryButton("onboarding.continue") { viewModel.goNext() }
                    if viewModel.notificationStatus != .authorized {
                        Text("onboarding.notif.skip.hint")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
        }
        .padding(32)
        .onAppear { viewModel.checkNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.checkNotificationStatus()
        }
    }

    private var notificationMockup: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text("onboarding.notif.mockup.title")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("onboarding.notif.mockup.body")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial.opacity(0.15))
        )
        .frame(maxWidth: 340)
    }

    @ViewBuilder
    private var actionArea: some View {
        switch viewModel.notificationStatus {
        case .unknown:
            ProgressView().tint(.white)
        case .notYetAsked:
            darkPrimaryButton("onboarding.notif.enable") { viewModel.requestNotifications() }
        case .authorized:
            VStack(spacing: 12) {
                Label {
                    Text("onboarding.notif.enabled")
                        .font(.system(size: 15, weight: .medium))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .foregroundStyle(.white)
                darkButton("onboarding.notif.test") { viewModel.sendTestNotification() }
            }
        case .denied:
            VStack(spacing: 12) {
                Text("onboarding.notif.denied.hint")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                darkButton("onboarding.notif.open.settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

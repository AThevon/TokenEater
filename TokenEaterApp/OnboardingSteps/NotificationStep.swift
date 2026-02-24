import SwiftUI

struct NotificationStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Bell icon
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            // Title
            Text("onboarding.notif.title")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            // Description
            Text("onboarding.notif.simple")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            // Notification mockup
            notificationMockup

            // Action area (depends on authorization state)
            actionArea

            Spacer()

            // Navigation
            bottomBar
        }
        .padding(32)
        .onAppear {
            viewModel.checkNotificationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.checkNotificationStatus()
        }
    }

    // MARK: - Notification Mockup

    private var notificationMockup: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text("onboarding.notif.mockup.title")
                    .font(.system(size: 12, weight: .semibold))
                Text("onboarding.notif.mockup.body")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .frame(maxWidth: 340)
    }

    // MARK: - Action Area

    @ViewBuilder
    private var actionArea: some View {
        switch viewModel.notificationStatus {
        case .unknown:
            ProgressView()
                .controlSize(.small)

        case .notYetAsked:
            Button {
                viewModel.requestNotifications()
            } label: {
                Label("onboarding.notif.enable", systemImage: "bell.badge")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .authorized:
            VStack(spacing: 12) {
                Label {
                    Text("onboarding.notif.enabled")
                        .font(.system(size: 15, weight: .medium))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button {
                    viewModel.sendTestNotification()
                } label: {
                    Label("onboarding.notif.test", systemImage: "paperplane")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

        case .denied:
            VStack(spacing: 12) {
                Text("onboarding.notif.denied.hint")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)

                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("onboarding.notif.open.settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                viewModel.goBack()
            } label: {
                Text("onboarding.back")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    viewModel.goNext()
                } label: {
                    Text("onboarding.continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                // Soft-gate hint
                if viewModel.notificationStatus != .authorized {
                    Text("onboarding.notif.skip.hint")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

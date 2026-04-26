import SwiftUI
import AppKit

/// Second card - optional. Toggle flick triggers the macOS notification
/// permission prompt. Once authorized the user can fire a test notification
/// from the meta footer; if denied, the toggle is replaced by a deep link
/// to System Settings > Notifications.
struct NotificationsCard: View {
    @ObservedObject var viewModel: OnboardingViewModel

    private let accent = Color(red: 1.0, green: 0.62, blue: 0.04) // amber

    var body: some View {
        OnboardingCard(
            kind: .optional,
            tilt: .right,
            title: "onboarding.card.notifications.title",
            statusText: statusText,
            statusColor: statusColor,
            accent: accent,
            scene: { scene },
            control: { control }
        )
        .onAppear { viewModel.checkNotificationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.checkNotificationStatus()
        }
    }

    @ViewBuilder
    private var scene: some View {
        switch viewModel.notificationStatus {
        case .unknown:
            ProgressView().tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .notYetAsked:
            stackedNotifPreview

        case .authorized:
            authorizedScene

        case .denied:
            deniedScene
        }
    }

    private var stackedNotifPreview: some View {
        ZStack(alignment: .center) {
            notifPreview(title: "TokenEater", body: "Weekly limit at 78%", time: "2m")
                .opacity(0.55)
                .scaleEffect(0.92)
                .rotationEffect(.degrees(0.6))
                .offset(y: -16)

            notifPreview(title: "TokenEater", body: "5h limit warming up", time: "now")
                .rotationEffect(.degrees(-1.2))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
    }

    private func notifPreview(title: String, body: String, time: String) -> some View {
        HStack(spacing: 7) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(body)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Text(time)
                .font(.system(size: 7.5))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: 200)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(red: 0.235, green: 0.235, blue: 0.255).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
    }

    private var authorizedScene: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 32, height: 32)
                Image(systemName: "bell.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(accent)
            }
            Text("onboarding.card.notifications.authorized.scene")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedScene: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().fill(Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.16)).frame(width: 32, height: 32)
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.94, green: 0.27, blue: 0.27))
            }
            Text("onboarding.card.notifications.denied.scene")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var control: some View {
        switch viewModel.notificationStatus {
        case .unknown:
            EmptyView()

        case .notYetAsked:
            Toggle("", isOn: Binding(
                get: { false },
                set: { newValue in if newValue { viewModel.requestNotifications() } }
            ))
            .toggleStyle(SwitchToggleStyle(tint: accent))
            .controlSize(.mini)
            .labelsHidden()

        case .authorized:
            Button {
                viewModel.sendTestNotification()
            } label: {
                Text("onboarding.card.notifications.test")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

        case .denied:
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("onboarding.card.notifications.opensettings")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.18)))
                    .overlay(Capsule().stroke(accent.opacity(0.32), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var statusText: LocalizedStringResource {
        switch viewModel.notificationStatus {
        case .unknown, .notYetAsked: return "onboarding.card.notifications.status.off"
        case .authorized:            return "onboarding.card.notifications.status.on"
        case .denied:                return "onboarding.card.notifications.status.denied"
        }
    }

    private var statusColor: Color {
        switch viewModel.notificationStatus {
        case .unknown, .notYetAsked: return Color.white.opacity(0.3)
        case .authorized:            return Color(red: 0.30, green: 0.81, blue: 0.50)
        case .denied:                return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }
}

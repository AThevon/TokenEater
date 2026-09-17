import SwiftUI

/// Offers Codex tracking on the dashboard when a usable login is sitting there
/// unused.
///
/// Deliberately an invitation and not a second switch. The permanent control
/// lives in Settings under Providers, and duplicating an on/off in two places
/// is how a settings surface starts feeling like a maze. What the dashboard
/// owes the user is discovery: you should not have to already know the feature
/// exists to find it. Once tracking is on, this disappears for good and the
/// Codex section takes its place.
struct CodexInvitationRow: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var codexStore: CodexUsageStore

    @State private var isDismissed = UserDefaults.standard.bool(forKey: Self.dismissedKey)

    private static let dismissedKey = "codexInvitationDismissed"

    /// A login that cannot be tracked, or one that has expired, is not an
    /// invitation: turning tracking on would only produce an error.
    private var shouldShow: Bool {
        !isDismissed
            && !settingsStore.codexEnabled
            && codexStore.authState.isTrackable
            && !codexStore.authState.isExpired()
    }

    var body: some View {
        if shouldShow {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.brandPrimary)

                Text("monitoring.codex.invitation")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button {
                    settingsStore.codexEnabled = true
                } label: {
                    Text("monitoring.codex.invitation.enable")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(DS.Palette.brandPrimary.opacity(0.22))
                        )
                        .foregroundStyle(DS.Palette.brandPrimary)
                }
                .buttonStyle(.plain)

                Button {
                    isDismissed = true
                    UserDefaults.standard.set(true, forKey: Self.dismissedKey)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("monitoring.codex.invitation.dismiss"))
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                            .stroke(DS.Palette.brandPrimary.opacity(0.18), lineWidth: 1)
                    )
            )
        }
    }
}

import SwiftUI

/// Settings sub-section dedicated to notifications. Hosts the authorization
/// status row + test button at the top, then a card per category (usage
/// thresholds / pacing / reset reminders / extra credits / health) with one
/// toggle per event.
struct NotificationsSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var notifTestCooldown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(
                String(localized: "sidebar.notifications"),
                subtitle: String(localized: "sidebar.notifications.subtitle")
            )

            authorizationCard
            usageCard
            pacingCard
            resetRemindersCard
            extraCreditsCard
            healthCard
        }
        .padding(24)
        .task { await settingsStore.refreshNotificationStatus() }
    }

    // MARK: - Authorization

    private var authorizationCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel(String(localized: "settings.notifications.status"))
                HStack {
                    statusLabel
                    Spacer()
                    if settingsStore.notificationStatus == .denied {
                        Button(String(localized: "settings.notifications.open")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings")!)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    } else if settingsStore.notificationStatus != .authorized {
                        Button(String(localized: "settings.notifications.enable")) {
                            settingsStore.requestNotificationPermission()
                            Task {
                                try? await Task.sleep(for: .seconds(1))
                                await settingsStore.refreshNotificationStatus()
                            }
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                    Button(String(localized: "settings.notifications.test")) {
                        if settingsStore.notificationStatus != .authorized {
                            settingsStore.requestNotificationPermission()
                        }
                        settingsStore.sendTestNotification()
                        notifTestCooldown = true
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            notifTestCooldown = false
                            await settingsStore.refreshNotificationStatus()
                        }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .disabled(notifTestCooldown)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch settingsStore.notificationStatus {
        case .authorized:
            Label(String(localized: "settings.notifications.on"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .denied:
            Label(String(localized: "settings.notifications.off"), systemImage: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        default:
            Label(String(localized: "settings.notifications.unknown"), systemImage: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Usage thresholds

    private var usageCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel(String(localized: "settings.notifications.group.usage"))
                Text(String(localized: "settings.notifications.group.usage.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                darkToggle(String(localized: "settings.notifications.track.fivehour"), isOn: $settingsStore.notifTrackFiveHour)
                darkToggle(String(localized: "settings.notifications.track.weekly"), isOn: $settingsStore.notifTrackWeekly)
                darkToggle(String(localized: "settings.notifications.track.sonnet"), isOn: $settingsStore.notifTrackSonnet)
                darkToggle(String(localized: "settings.notifications.track.design"), isOn: $settingsStore.notifTrackDesign)
                Divider().padding(.vertical, 2)
                darkToggle(String(localized: "settings.notifications.recovery"), isOn: $settingsStore.notifSendRecovery)
                Text(String(localized: "settings.notifications.recovery.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Pacing

    private var pacingCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel(String(localized: "settings.notifications.group.pacing"))
                Text(String(localized: "settings.notifications.group.pacing.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                darkToggle(String(localized: "settings.notifications.pacing.hot"), isOn: $settingsStore.notifPacingHot)
                darkToggle(String(localized: "settings.notifications.pacing.warning"), isOn: $settingsStore.notifPacingWarning)
            }
        }
    }

    // MARK: - Reset reminders

    private var resetRemindersCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel(String(localized: "settings.notifications.group.reset"))
                Text(String(localized: "settings.notifications.group.reset.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                darkToggle(String(localized: "settings.notifications.reset.session"), isOn: $settingsStore.notifResetReminderSession)
                darkToggle(String(localized: "settings.notifications.reset.weekly"), isOn: $settingsStore.notifResetReminderWeekly)
            }
        }
    }

    // MARK: - Extra credits

    private var extraCreditsCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel(String(localized: "settings.notifications.group.extra"))
                Text(String(localized: "settings.notifications.group.extra.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                darkToggle(String(localized: "settings.notifications.extra"), isOn: $settingsStore.notifExtraCredits)
            }
        }
    }

    // MARK: - Health

    private var healthCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel(String(localized: "settings.notifications.group.health"))
                Text(String(localized: "settings.notifications.group.health.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                darkToggle(String(localized: "settings.notifications.token"), isOn: $settingsStore.notifTokenExpired)
            }
        }
    }
}

import SwiftUI

/// Settings sub-section dedicated to notifications.
///
/// One row per event, one column per provider. The page used to be five cards
/// of Claude events grouped by theme, plus a sixth card holding every OpenAI
/// event in a heap, so the same setting lived in two different places
/// depending on the provider and the differences between them were invisible.
/// Rows and columns say it in one shape: what each event is, who supports it,
/// and what is on, with a dash where a provider genuinely has no such event.
///
/// It is the Coverage page's grid, applied to settings.
struct NotificationsSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var notifTestCooldown = false

    /// Wide enough for a mini switch plus breathing room, and identical in
    /// every card so the columns line up down the whole page.
    private let columnWidth: CGFloat = 58

    private var providers: [MetricProvider] { settingsStore.activeProviders }

    /// One provider needs no columns: the rows have a single switch and the
    /// page reads exactly as it did before modes existed.
    private var showsColumns: Bool { providers.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                sectionTitle(
                    String(localized: "sidebar.notifications"),
                    subtitle: String(localized: "sidebar.notifications.subtitle")
                )
                Spacer()
                ClickChip(
                    label: String(localized: "settings.notifications.master"),
                    icon: settingsStore.notificationsEnabled ? "checkmark" : "bell.slash",
                    isActive: settingsStore.notificationsEnabled,
                    accent: .blue,
                    style: .compact
                ) {
                    settingsStore.notificationsEnabled.toggle()
                }
            }

            authorizationCard
            if showsColumns { providerCard }
            usageCard
            pacingCard
            resetRemindersCard
            extraCreditsCard
            healthCard

            ResetSectionButton(
                confirmTitle: String(localized: "settings.notifications.reset.confirm"),
                onReset: resetToDefaults
            )
        }
        .padding(24)
        .task { await settingsStore.refreshNotificationStatus() }
    }

    private func resetToDefaults() {
        settingsStore.notificationsEnabled = true
        settingsStore.notification.claudeEnabled = true
        settingsStore.notifTrackFiveHour = true
        settingsStore.notifTrackWeekly = true
        settingsStore.notifTrackSonnet = false
        settingsStore.notifTrackFable = true
        settingsStore.notifSendRecovery = true
        settingsStore.notifPacingHot = true
        settingsStore.notifPacingWarning = false
        settingsStore.notifResetReminderSession = false
        settingsStore.notifResetReminderWeekly = false
        settingsStore.notifResetReminderSessionOffset = 15
        settingsStore.notifResetReminderWeeklyOffset = 60
        settingsStore.notifExtraCredits = true
        settingsStore.notifTokenExpired = false
        settingsStore.notifVendorDegraded = true
        settingsStore.notifVendorRestored = true
        settingsStore.notification.codexEnabled = true
        settingsStore.notification.codexTrackSession = true
        settingsStore.notification.codexTrackWeekly = true
        settingsStore.notification.codexWindowReset = true
        settingsStore.notification.codexResetReminderSession = false
        settingsStore.notification.codexResetReminderWeekly = false
        settingsStore.notification.codexTokenExpired = true
    }

    // MARK: - Provider columns

    /// The column header, and the only place a whole provider can be silenced.
    private var providerCard: some View {
        glassCard {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    cardLabel(String(localized: "settings.notifications.group.providers"))
                    Text(String(localized: "settings.notifications.group.providers.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ForEach(providers) { provider in
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            ProviderGlyph(provider: provider, size: 11)
                                .foregroundStyle(master(provider).wrappedValue
                                                 ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                            Text(provider.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(master(provider).wrappedValue
                                                 ? DS.Palette.textSecondary : DS.Palette.textTertiary)
                        }
                        bareToggle(master(provider))
                    }
                    .frame(width: columnWidth)
                }
            }
        }
    }

    private func master(_ provider: MetricProvider) -> Binding<Bool> {
        switch provider {
        case .claude: return $settingsStore.notification.claudeEnabled
        case .codex:  return $settingsStore.notification.codexEnabled
        }
    }

    // MARK: - Rows

    /// One event, one cell per provider. A provider with no binding for the
    /// event gets a dash rather than a dead switch: the event does not exist
    /// there, which is a different thing from being turned off.
    @ViewBuilder
    private func eventRow(
        _ label: String,
        hint: String? = nil,
        _ bindings: [MetricProvider: Binding<Bool>]
    ) -> some View {
        if providers.contains(where: { bindings[$0] != nil }) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textPrimary)
                    if let hint {
                        Text(hint)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.38))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                ForEach(providers) { provider in
                    cell(for: provider, binding: bindings[provider])
                        .frame(width: showsColumns ? columnWidth : nil)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for provider: MetricProvider, binding: Binding<Bool>?) -> some View {
        if let binding {
            bareToggle(binding)
                .disabled(!master(provider).wrappedValue)
                .opacity(master(provider).wrappedValue ? 1 : 0.35)
        } else {
            Text(verbatim: "\u{2013}")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.16))
                .help(String(format: String(localized: "settings.notifications.unsupported"),
                             provider.displayName))
        }
    }

    /// A setting that is deliberately one setting for every provider. It gets
    /// the mark rather than a duplicated switch per column, because splitting
    /// it would be inventing a preference nobody asked for.
    private func sharedRow(_ label: String, hint: String? = nil, _ binding: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textPrimary)
                if let hint {
                    Text(hint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if showsColumns { sharedMark }
            bareToggle(binding)
                .frame(width: showsColumns ? columnWidth : nil)
        }
    }

    private var sharedMark: some View {
        Text(String(localized: "settings.notifications.shared"))
            .font(.system(size: 8, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .help(String(localized: "settings.notifications.shared.hint"))
    }

    private func bareToggle(_ binding: Binding<Bool>) -> some View {
        Toggle("", isOn: binding)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
    }

    private func groupHeader(_ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            cardLabel(title)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
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
                        sendTests()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .disabled(notifTestCooldown)
                    .help(String(localized: "settings.notifications.test.hint"))
                }
            }
        }
    }

    /// One test per tracked provider, so the banner shows the subtitle and the
    /// grouping the real alerts will use rather than an anonymous sample.
    private func sendTests() {
        if settingsStore.notificationStatus != .authorized {
            settingsStore.requestNotificationPermission()
        }
        if providers.isEmpty {
            settingsStore.sendTestNotification()
        } else {
            for provider in providers {
                settingsStore.sendTestNotification(for: provider)
            }
        }
        notifTestCooldown = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            notifTestCooldown = false
            await settingsStore.refreshNotificationStatus()
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
                groupHeader(String(localized: "settings.notifications.group.usage"),
                            String(localized: "settings.notifications.group.usage.hint"))
                eventRow(String(localized: "settings.notifications.row.session"), [
                    .claude: $settingsStore.notification.trackFiveHour,
                    .codex: $settingsStore.notification.codexTrackSession,
                ])
                eventRow(String(localized: "settings.notifications.row.weekly"), [
                    .claude: $settingsStore.notification.trackWeekly,
                    .codex: $settingsStore.notification.codexTrackWeekly,
                ])
                eventRow(String(localized: "settings.notifications.row.sonnet"), [
                    .claude: $settingsStore.notification.trackSonnet,
                ])
                eventRow(String(localized: "settings.notifications.row.fable"), [
                    .claude: $settingsStore.notification.trackFable,
                ])
                Divider().padding(.vertical, 2)
                // Two mechanisms, one meaning. Claude fires its recovery alert
                // only once the window has genuinely rolled over, which is the
                // same event OpenAI's window-reset detector reports, so they
                // belong on one row rather than in two different cards.
                eventRow(String(localized: "settings.notifications.row.recovery"),
                         hint: String(localized: "settings.notifications.row.recovery.hint"), [
                    .claude: $settingsStore.notification.sendRecovery,
                    .codex: $settingsStore.notification.codexWindowReset,
                ])
            }
        }
    }

    // MARK: - Pacing

    private var pacingCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                groupHeader(String(localized: "settings.notifications.group.pacing"),
                            String(localized: "settings.notifications.group.pacing.hint"))
                sharedRow(String(localized: "settings.notifications.pacing.hot"),
                          $settingsStore.notification.pacingHot)
                sharedRow(String(localized: "settings.notifications.pacing.warning"),
                          $settingsStore.notification.pacingWarning)
            }
        }
    }

    // MARK: - Reset reminders

    private var resetRemindersCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                groupHeader(String(localized: "settings.notifications.group.reset"),
                            String(localized: "settings.notifications.group.reset.hint"))
                eventRow(String(localized: "settings.notifications.reset.session"), [
                    .claude: $settingsStore.notification.resetReminderSession,
                    .codex: $settingsStore.notification.codexResetReminderSession,
                ])
                reminderOffsetPicker(
                    selection: $settingsStore.notification.resetReminderSessionOffset,
                    options: [5, 10, 15, 30, 60],
                    enabled: settingsStore.notification.resetReminderSession
                        || settingsStore.notification.codexResetReminderSession
                )
                eventRow(String(localized: "settings.notifications.reset.weekly"), [
                    .claude: $settingsStore.notification.resetReminderWeekly,
                    .codex: $settingsStore.notification.codexResetReminderWeekly,
                ])
                reminderOffsetPicker(
                    selection: $settingsStore.notification.resetReminderWeeklyOffset,
                    options: [30, 60, 120, 180, 360],
                    enabled: settingsStore.notification.resetReminderWeekly
                        || settingsStore.notification.codexResetReminderWeekly
                )
            }
        }
    }

    @ViewBuilder
    private func reminderOffsetPicker(selection: Binding<Int>, options: [Int], enabled: Bool) -> some View {
        HStack(spacing: 6) {
            Text(String(localized: "settings.notifications.reset.offset.label"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(enabled ? 0.6 : 0.25))
            Spacer()
            if showsColumns { sharedMark }
            DSMenu(
                selection: selection,
                options: options,
                label: formatOffsetMinutes,
                enabled: enabled
            )
        }
        .padding(.leading, 12)
    }

    private func formatOffsetMinutes(_ minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return String(format: String(localized: "settings.notifications.reset.offset.hours"), hours)
        }
        return String(format: String(localized: "settings.notifications.reset.offset.minutes"), minutes)
    }

    // MARK: - Extra credits

    @ViewBuilder
    private var extraCreditsCard: some View {
        if providers.contains(.claude) {
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    groupHeader(String(localized: "settings.notifications.group.extra"),
                                String(localized: "settings.notifications.group.extra.hint"))
                    eventRow(String(localized: "settings.notifications.extra"), [
                        .claude: $settingsStore.notification.extraCredits,
                    ])
                }
            }
        }
    }

    // MARK: - Health

    private var healthCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                groupHeader(String(localized: "settings.notifications.group.health"),
                            String(localized: "settings.notifications.group.health.hint"))
                eventRow(String(localized: "settings.notifications.row.credentials"), [
                    .claude: $settingsStore.notification.tokenExpired,
                    .codex: $settingsStore.notification.codexTokenExpired,
                ])
                eventRow(String(localized: "settings.notifications.status.degraded"), [
                    .claude: $settingsStore.notification.vendorDegraded,
                ])
                eventRow(String(localized: "settings.notifications.status.restored"), [
                    .claude: $settingsStore.notification.vendorRestored,
                ])
            }
        }
    }
}

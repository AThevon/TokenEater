import SwiftUI

/// Settings sub-section for vendor outage monitoring: master switch, healthy
/// poll cadence, and the menu-bar badge toggle. Degraded/restored notification
/// toggles live in the Notifications section's Health card.
struct ServiceStatusSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                sectionTitle(
                    String(localized: "sidebar.serviceStatus"),
                    subtitle: String(localized: "sidebar.serviceStatus.subtitle")
                )
                Spacer()
                ClickChip(
                    label: String(localized: "settings.status.master"),
                    icon: settingsStore.outageMonitoringEnabled ? "checkmark" : "bolt.slash",
                    isActive: settingsStore.outageMonitoringEnabled,
                    accent: .blue,
                    style: .compact
                ) {
                    settingsStore.outageMonitoringEnabled.toggle()
                }
            }

            pollingCard
            displayCard

            ResetSectionButton(
                confirmTitle: String(localized: "settings.status.reset.confirm"),
                onReset: resetToDefaults
            )
        }
        .padding(24)
    }

    private func resetToDefaults() {
        settingsStore.outageMonitoringEnabled = true
        settingsStore.statusPollInterval = 300
        settingsStore.statusShowMenuBarBadge = true
    }

    // MARK: - Polling

    private var pollingCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 8) {
                cardLabel(String(localized: "settings.status.group.polling"))
                Text(String(localized: "settings.status.group.polling.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(String(localized: "settings.status.interval.label"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(formatInterval(settingsStore.statusPollInterval))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                }
                TokenEaterSlider(
                    value: Binding(
                        get: { Double(settingsStore.statusPollInterval) },
                        set: { settingsStore.statusPollInterval = Int($0) }
                    ),
                    in: 60...1800,
                    step: 60,
                    showsTicks: true
                )
            }
        }
    }

    private func formatInterval(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return String(format: String(localized: "settings.status.interval.minutes"), minutes)
    }

    // MARK: - Display

    private var displayCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 10) {
                cardLabel(String(localized: "settings.status.group.display"))
                darkToggle(String(localized: "settings.status.badge"), isOn: $settingsStore.statusShowMenuBarBadge)
            }
        }
    }
}

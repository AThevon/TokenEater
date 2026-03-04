import SwiftUI

struct PerformanceSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle(String(localized: "sidebar.performance"))

                Text("settings.performance.description")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)

                // Dashboard
                glassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        cardLabel(String(localized: "settings.performance.dashboard"))
                        darkToggle(String(localized: "settings.performance.particles"), isOn: $settingsStore.particlesEnabled)
                        darkToggle(String(localized: "settings.performance.gradient"), isOn: $settingsStore.animatedGradientEnabled)
                    }
                }

                // Agent Watchers
                glassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        cardLabel(String(localized: "settings.performance.watchers"))
                        darkToggle(String(localized: "settings.performance.animations"), isOn: $settingsStore.watcherAnimationsEnabled)
                    }
                }

                // Session Monitor
                glassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        cardLabel(String(localized: "settings.performance.monitor"))
                        darkToggle(String(localized: "settings.performance.monitor.toggle"), isOn: $settingsStore.sessionMonitorEnabled)

                        Text("settings.performance.monitor.warning")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
        }
    }
}

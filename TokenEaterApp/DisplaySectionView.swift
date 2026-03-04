import SwiftUI

struct DisplaySectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore

    // Local @State bindings — stable across body re-evaluations.
    // Binding to computed properties via $store.computedProp creates
    // unstable LocationProjections that the AttributeGraph can never
    // memoize, causing an infinite re-evaluation loop in Release builds.
    @State private var showFiveHour: Bool
    @State private var showSevenDay: Bool
    @State private var showSonnet: Bool
    @State private var showPacing: Bool

    init(initialMetrics: Set<MetricID>) {
        _showFiveHour = State(initialValue: initialMetrics.contains(.fiveHour))
        _showSevenDay = State(initialValue: initialMetrics.contains(.sevenDay))
        _showSonnet = State(initialValue: initialMetrics.contains(.sonnet))
        _showPacing = State(initialValue: initialMetrics.contains(.pacing))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(String(localized: "sidebar.display"))

            // Menu Bar
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.menubar.title"))
                    darkToggle(String(localized: "settings.menubar.toggle"), isOn: $settingsStore.showMenuBar)
                    darkToggle(String(localized: "settings.theme.monochrome"), isOn: $themeStore.menuBarMonochrome)
                }
            }

            // Pinned Metrics
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.metrics.pinned"))
                    darkToggle(String(localized: "metric.session"), isOn: $showFiveHour)
                    darkToggle(String(localized: "metric.weekly"), isOn: $showSevenDay)
                    darkToggle(String(localized: "metric.sonnet"), isOn: $showSonnet)
                    darkToggle(String(localized: "pacing.label"), isOn: $showPacing)
                    if showPacing {
                        PacingDisplayPicker(selection: $settingsStore.pacingDisplayMode)
                            .padding(.leading, 8)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        // Sync: local toggle -> store (with at-least-one guard)
        .onChange(of: showFiveHour) { _, new in syncMetric(.fiveHour, on: new, revert: { showFiveHour = true }) }
        .onChange(of: showSevenDay) { _, new in syncMetric(.sevenDay, on: new, revert: { showSevenDay = true }) }
        .onChange(of: showSonnet) { _, new in syncMetric(.sonnet, on: new, revert: { showSonnet = true }) }
        .onChange(of: showPacing) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) {
                syncMetric(.pacing, on: new, revert: { showPacing = true })
            }
        }
        // Sync: store -> local toggles (for external changes, e.g. from MenuBar popover)
        .onChange(of: settingsStore.pinnedMetrics) { _, metrics in
            if showFiveHour != metrics.contains(.fiveHour) { showFiveHour = metrics.contains(.fiveHour) }
            if showSevenDay != metrics.contains(.sevenDay) { showSevenDay = metrics.contains(.sevenDay) }
            if showSonnet != metrics.contains(.sonnet) { showSonnet = metrics.contains(.sonnet) }
            if showPacing != metrics.contains(.pacing) {
                withAnimation(.easeInOut(duration: 0.2)) { showPacing = metrics.contains(.pacing) }
            }
        }
    }

    private func syncMetric(_ metric: MetricID, on: Bool, revert: @escaping () -> Void) {
        if on {
            settingsStore.pinnedMetrics.insert(metric)
        } else if settingsStore.pinnedMetrics.count > 1 {
            settingsStore.pinnedMetrics.remove(metric)
        } else {
            revert()
        }
    }
}

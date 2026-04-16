import SwiftUI

struct DisplaySectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore

    // Local @State bindings - stable across body re-evaluations.
    // Binding to computed properties via $store.computedProp creates
    // unstable LocationProjections that the AttributeGraph can never
    // memoize, causing an infinite re-evaluation loop in Release builds.
    @State private var showFiveHour: Bool
    @State private var showSevenDay: Bool
    @State private var showSonnet: Bool
    @State private var showSessionPacing: Bool
    @State private var showWeeklyPacing: Bool
    @State private var showSonnetPacing: Bool

    init(initialMetrics: Set<MetricID>) {
        _showFiveHour = State(initialValue: initialMetrics.contains(.fiveHour))
        _showSevenDay = State(initialValue: initialMetrics.contains(.sevenDay))
        _showSonnet = State(initialValue: initialMetrics.contains(.sonnet))
        _showSessionPacing = State(initialValue: initialMetrics.contains(.sessionPacing))
        _showWeeklyPacing = State(initialValue: initialMetrics.contains(.weeklyPacing))
        _showSonnetPacing = State(initialValue: initialMetrics.contains(.sonnetPacing))
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
                    darkToggle(String(localized: "settings.display.sonnet"), isOn: $settingsStore.displaySonnet)
                }
            }

            // Pinned Metrics
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.metrics.pinned"))
                    darkToggle(String(localized: "metric.session"), isOn: $showFiveHour)
                    if showFiveHour {
                        darkToggle(String(localized: "settings.session.reset"), isOn: $settingsStore.showSessionReset)
                    }
                    darkToggle(String(localized: "metric.weekly"), isOn: $showSevenDay)
                    if settingsStore.displaySonnet {
                        darkToggle(String(localized: "metric.sonnet"), isOn: $showSonnet)
                    }
                    darkToggle(String(localized: "pacing.session.label"), isOn: $showSessionPacing)
                    darkToggle(String(localized: "pacing.weekly.label"), isOn: $showWeeklyPacing)
                    if settingsStore.displaySonnet {
                        darkToggle(String(localized: "pacing.sonnet.label"), isOn: $showSonnetPacing)
                    }
                    if showSessionPacing || showWeeklyPacing || (settingsStore.displaySonnet && showSonnetPacing) {
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
        .onChange(of: showSessionPacing) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) {
                syncMetric(.sessionPacing, on: new, revert: { showSessionPacing = true })
            }
        }
        .onChange(of: showWeeklyPacing) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) {
                syncMetric(.weeklyPacing, on: new, revert: { showWeeklyPacing = true })
            }
        }
        .onChange(of: showSonnetPacing) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) {
                syncMetric(.sonnetPacing, on: new, revert: { showSonnetPacing = true })
            }
        }
        // Sync: store -> local toggles (for external changes, e.g. from MenuBar popover)
        .onChange(of: settingsStore.pinnedMetrics) { _, metrics in
            if showFiveHour != metrics.contains(.fiveHour) { showFiveHour = metrics.contains(.fiveHour) }
            if showSevenDay != metrics.contains(.sevenDay) { showSevenDay = metrics.contains(.sevenDay) }
            if showSonnet != metrics.contains(.sonnet) { showSonnet = metrics.contains(.sonnet) }
            if showSessionPacing != metrics.contains(.sessionPacing) {
                withAnimation(.easeInOut(duration: 0.2)) { showSessionPacing = metrics.contains(.sessionPacing) }
            }
            if showWeeklyPacing != metrics.contains(.weeklyPacing) {
                withAnimation(.easeInOut(duration: 0.2)) { showWeeklyPacing = metrics.contains(.weeklyPacing) }
            }
            if showSonnetPacing != metrics.contains(.sonnetPacing) {
                withAnimation(.easeInOut(duration: 0.2)) { showSonnetPacing = metrics.contains(.sonnetPacing) }
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

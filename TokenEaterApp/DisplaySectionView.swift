import SwiftUI

struct DisplaySectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore

    // Local @State bindings — stable across body re-evaluations.
    // Binding to computed properties via $store.computedProp creates
    // unstable LocationProjections that the AttributeGraph can never
    // memoize, causing an infinite re-evaluation loop in Release builds.
    @State private var showFiveHour = true
    @State private var showSevenDay = true
    @State private var showSonnet = false
    @State private var showPacing = false
    @State private var marginSliderValue: Double = 10

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
                        marginSlider(value: $marginSliderValue)
                            .padding(.leading, 8)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        // Initialize local state from stores
        .task {
            showFiveHour = settingsStore.pinnedMetrics.contains(.fiveHour)
            showSevenDay = settingsStore.pinnedMetrics.contains(.sevenDay)
            showSonnet = settingsStore.pinnedMetrics.contains(.sonnet)
            showPacing = settingsStore.pinnedMetrics.contains(.pacing)
            marginSliderValue = Double(settingsStore.pacingMargin)
        }
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
        // Sync: pacing margin slider <-> store
        .onChange(of: marginSliderValue) { _, new in
            let int = Int(new)
            if settingsStore.pacingMargin != int { settingsStore.pacingMargin = int }
        }
        .onChange(of: settingsStore.pacingMargin) { _, new in
            let d = Double(new)
            if marginSliderValue != d { marginSliderValue = d }
        }
    }

    private func marginSlider(value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(String(localized: "settings.pacing.margin"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            Slider(value: value, in: 5...25, step: 1)
                .tint(.blue)
            Text("\u{00B1}\(Int(value.wrappedValue))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 44, alignment: .trailing)
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

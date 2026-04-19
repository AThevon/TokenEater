import SwiftUI

struct DisplaySectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore

    // Local @State bindings - stable across body re-evaluations.
    // Binding to computed properties via $store.computedProp creates
    // unstable LocationProjections that the AttributeGraph can never
    // memoize, causing an infinite re-evaluation loop in Release builds.
    @State private var showFiveHour: Bool
    @State private var showSessionReset: Bool
    @State private var showSessionPacing: Bool
    @State private var showSevenDay: Bool
    @State private var showWeeklyPacing: Bool
    @State private var showSonnet: Bool

    init(initialMetrics: Set<MetricID>) {
        _showFiveHour = State(initialValue: initialMetrics.contains(.fiveHour))
        _showSessionReset = State(initialValue: initialMetrics.contains(.sessionReset))
        _showSessionPacing = State(initialValue: initialMetrics.contains(.sessionPacing))
        _showSevenDay = State(initialValue: initialMetrics.contains(.sevenDay))
        _showWeeklyPacing = State(initialValue: initialMetrics.contains(.weeklyPacing))
        _showSonnet = State(initialValue: initialMetrics.contains(.sonnet))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(String(localized: "sidebar.display"))

            // 1. Menu bar visibility
            glassCard {
                darkToggle(String(localized: "settings.menubar.toggle"), isOn: $settingsStore.showMenuBar)
            }

            // 2. Pinned metrics live preview
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardLabel(String(localized: "settings.metrics.pinned"))
                    menuBarPreview
                }
            }

            // 3. Session (5h)
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardLabel(String(localized: "settings.group.session"))
                    darkToggle(String(localized: "metric.session"), isOn: $showFiveHour)
                    toggleWithTrailing(
                        label: String(localized: "metric.sessionReset"),
                        isOn: $showSessionReset
                    ) {
                        if showSessionReset {
                            ResetFormatPicker(selection: $settingsStore.resetDisplayFormat)
                                .labelsHidden()
                                .frame(maxWidth: 160)
                        }
                    }
                    toggleWithTrailing(
                        label: String(localized: "pacing.session.label"),
                        isOn: $showSessionPacing
                    ) {
                        if showSessionPacing {
                            PacingDisplayPicker(selection: $settingsStore.sessionPacingDisplayMode)
                                .labelsHidden()
                                .frame(maxWidth: 160)
                        }
                    }
                }
            }

            // 4. Weekly
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardLabel(String(localized: "settings.group.weekly"))
                    darkToggle(String(localized: "metric.weekly"), isOn: $showSevenDay)
                    toggleWithTrailing(
                        label: String(localized: "pacing.weekly.label"),
                        isOn: $showWeeklyPacing
                    ) {
                        if showWeeklyPacing {
                            PacingDisplayPicker(selection: $settingsStore.weeklyPacingDisplayMode)
                                .labelsHidden()
                                .frame(maxWidth: 160)
                        }
                    }
                }
            }

            // 5. Sonnet
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardLabel(String(localized: "settings.group.sonnet"))
                    darkToggle(String(localized: "settings.display.sonnet"), isOn: $settingsStore.displaySonnet)
                    if settingsStore.displaySonnet {
                        darkToggle(String(localized: "metric.sonnet"), isOn: $showSonnet)
                            .padding(.leading, 20)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        // Sync: local toggle -> store (with at-least-one guard)
        .onChange(of: showFiveHour) { _, new in syncMetric(.fiveHour, on: new, revert: { showFiveHour = true }) }
        .onChange(of: showSessionReset) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) {
                syncMetric(.sessionReset, on: new, revert: { showSessionReset = true })
            }
        }
        .onChange(of: showSessionPacing) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) {
                syncMetric(.sessionPacing, on: new, revert: { showSessionPacing = true })
            }
        }
        .onChange(of: showSevenDay) { _, new in syncMetric(.sevenDay, on: new, revert: { showSevenDay = true }) }
        .onChange(of: showWeeklyPacing) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) {
                syncMetric(.weeklyPacing, on: new, revert: { showWeeklyPacing = true })
            }
        }
        .onChange(of: showSonnet) { _, new in syncMetric(.sonnet, on: new, revert: { showSonnet = true }) }
        // Sync: store -> local toggles (external changes, e.g. pin/unpin from popover)
        .onChange(of: settingsStore.pinnedMetrics) { _, metrics in
            if showFiveHour != metrics.contains(.fiveHour) { showFiveHour = metrics.contains(.fiveHour) }
            if showSessionReset != metrics.contains(.sessionReset) {
                withAnimation(.easeInOut(duration: 0.2)) { showSessionReset = metrics.contains(.sessionReset) }
            }
            if showSessionPacing != metrics.contains(.sessionPacing) {
                withAnimation(.easeInOut(duration: 0.2)) { showSessionPacing = metrics.contains(.sessionPacing) }
            }
            if showSevenDay != metrics.contains(.sevenDay) { showSevenDay = metrics.contains(.sevenDay) }
            if showWeeklyPacing != metrics.contains(.weeklyPacing) {
                withAnimation(.easeInOut(duration: 0.2)) { showWeeklyPacing = metrics.contains(.weeklyPacing) }
            }
            if showSonnet != metrics.contains(.sonnet) { showSonnet = metrics.contains(.sonnet) }
        }
    }

    // MARK: - Components

    private func toggleWithTrailing<Trailing: View>(
        label: String,
        isOn: Binding<Bool>,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(.blue)
                .labelsHidden()
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            trailing()
        }
    }

    private var menuBarPreview: some View {
        let image = MenuBarRenderer.renderUncached(previewData)
        return Image(nsImage: image)
            .interpolation(.high)
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.45))
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
            )
    }

    private var previewData: MenuBarRenderer.RenderData {
        MenuBarRenderer.RenderData(
            pinnedMetrics: settingsStore.pinnedMetrics,
            displaySonnet: settingsStore.displaySonnet,
            fiveHourPct: 45,
            sevenDayPct: 72,
            sonnetPct: 30,
            weeklyPacingDelta: 2,
            weeklyPacingZone: .onTrack,
            hasWeeklyPacing: true,
            sessionPacingDelta: -15,
            sessionPacingZone: .chill,
            hasSessionPacing: true,
            sessionPacingDisplayMode: settingsStore.sessionPacingDisplayMode,
            weeklyPacingDisplayMode: settingsStore.weeklyPacingDisplayMode,
            hasConfig: true,
            hasError: false,
            themeColors: themeStore.current,
            thresholds: themeStore.thresholds,
            menuBarMonochrome: themeStore.menuBarMonochrome,
            fiveHourReset: "1h58",
            fiveHourResetAbsolute: "20:30",
            fiveHourResetDate: Date().addingTimeInterval(1 * 3600 + 58 * 60),
            hasFiveHourBucket: true,
            resetDisplayFormat: settingsStore.resetDisplayFormat,
            resetTextColorHex: settingsStore.resetTextColorHex,
            sessionPeriodColorHex: settingsStore.sessionPeriodColorHex,
            smartResetColor: settingsStore.smartResetColor
        )
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

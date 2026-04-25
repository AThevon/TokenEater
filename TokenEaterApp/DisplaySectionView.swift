import SwiftUI

struct DisplaySectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var usageStore: UsageStore

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
    @State private var showDesign: Bool

    init(initialMetrics: Set<MetricID>) {
        _showFiveHour = State(initialValue: initialMetrics.contains(.fiveHour))
        _showSessionReset = State(initialValue: initialMetrics.contains(.sessionReset))
        _showSessionPacing = State(initialValue: initialMetrics.contains(.sessionPacing))
        _showSevenDay = State(initialValue: initialMetrics.contains(.sevenDay))
        _showWeeklyPacing = State(initialValue: initialMetrics.contains(.weeklyPacing))
        _showSonnet = State(initialValue: initialMetrics.contains(.sonnet))
        _showDesign = State(initialValue: initialMetrics.contains(.design))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(
                String(localized: "sidebar.display"),
                subtitle: String(localized: "sidebar.display.subtitle")
            )

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

            // 3. Menu bar style (font / separator / labels) + Pacing shape
            glassCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        cardLabel(String(localized: "settings.menubar.style"))
                        HStack(spacing: 8) {
                            ForEach(MenuBarStyle.allCases) { style in
                                menuBarStyleButton(style)
                            }
                        }
                    }

                    Divider().opacity(0.15)

                    VStack(alignment: .leading, spacing: 10) {
                        cardLabel(String(localized: "settings.pacing.shape"))
                        HStack(spacing: 8) {
                            ForEach(PacingShape.allCases) { shape in
                                pacingShapeButton(shape)
                            }
                        }
                    }
                }
            }

            // 4. Menu bar text appearance (monochrome + custom colors).
            // The reset countdown coloring is governed by the global "Smart
            // Color" toggle in Themes -> when enabled, the reset color picker
            // becomes informational (Smart drives the actual color).
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardLabel(String(localized: "settings.theme.menubar"))
                    darkToggle(String(localized: "settings.theme.monochrome"), isOn: $themeStore.menuBarMonochrome)
                    if !themeStore.menuBarMonochrome {
                        Divider().opacity(0.15)
                        menuBarColorRow(
                            label: "settings.reset.color",
                            hex: $settingsStore.resetTextColorHex,
                            fallback: .white,
                            disabled: settingsStore.smartColorEnabled
                        )
                        menuBarColorRow(
                            label: "settings.session.periodcolor",
                            hex: $settingsStore.sessionPeriodColorHex,
                            fallback: .white.opacity(0.4),
                            disabled: false
                        )
                    }
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

            // 5. Extra metrics (menu bar pins only - popover visibility is
            // handled in the Popover section)
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardLabel(String(localized: "settings.group.extra"))
                    darkToggle(String(localized: "metric.sonnet"), isOn: $showSonnet)
                    if usageStore.hasDesign {
                        darkToggle(String(localized: "metric.design"), isOn: $showDesign)
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
        .onChange(of: showDesign) { _, new in syncMetric(.design, on: new, revert: { showDesign = true }) }
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

    private func pacingShapeButton(_ shape: PacingShape) -> some View {
        let isActive = settingsStore.pacingShape == shape
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                settingsStore.pacingShape = shape
            }
        } label: {
            VStack(spacing: 6) {
                Text(shape.glyph)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.55))
                Text(shape.localizedLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? .white.opacity(0.9) : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color.blue.opacity(0.2) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isActive ? Color.blue.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Menu-bar text color row -> empty hex falls back to a system color and
    /// shows a revert-to-default button when the user has picked a custom color.
    private func menuBarColorRow(
        label: LocalizedStringKey,
        hex: Binding<String>,
        fallback: Color,
        disabled: Bool = false
    ) -> some View {
        let colorBinding = Binding<Color>(
            get: {
                hex.wrappedValue.isEmpty ? fallback : Color(hex: hex.wrappedValue)
            },
            set: { newColor in
                let nsColor = NSColor(newColor).usingColorSpace(.sRGB) ?? NSColor(newColor)
                hex.wrappedValue = nsColor.hexString()
            }
        )
        return HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(disabled ? 0.35 : 0.7))
            Spacer()
            if !hex.wrappedValue.isEmpty && !disabled {
                Button {
                    hex.wrappedValue = ""
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .help(Text(String(localized: "settings.theme.menubar.resetColor")))
            }
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .disabled(disabled)
                .opacity(disabled ? 0.4 : 1)
        }
    }

    private func menuBarStyleButton(_ style: MenuBarStyle) -> some View {
        let isActive = settingsStore.menuBarStyle == style
        return Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                settingsStore.menuBarStyle = style
            }
        } label: {
            Text(style.localizedLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? .white : .white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color.blue.opacity(0.2) : Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isActive ? Color.blue.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
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
            sevenDayResetDate: Date().addingTimeInterval(2 * 24 * 3600),
            sonnetResetDate: Date().addingTimeInterval(2 * 24 * 3600),
            designResetDate: Date().addingTimeInterval(2 * 24 * 3600),
            hasFiveHourBucket: true,
            resetDisplayFormat: settingsStore.resetDisplayFormat,
            resetTextColorHex: settingsStore.resetTextColorHex,
            sessionPeriodColorHex: settingsStore.sessionPeriodColorHex,
            smartResetColor: settingsStore.smartColorEnabled,
            menuBarStyle: settingsStore.menuBarStyle,
            pacingShape: settingsStore.pacingShape,
            designPct: 28,
            hasDesign: true
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

import SwiftUI

struct ThemesSectionView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var usageStore: UsageStore

    @State private var showResetAlert = false
    @State private var showSmartColorPopover = false
    @State private var warningSlider: Double
    @State private var criticalSlider: Double
    @State private var marginSlider: Double

    init(initialWarning: Int, initialCritical: Int, initialMargin: Int) {
        _warningSlider = State(initialValue: Double(initialWarning))
        _criticalSlider = State(initialValue: Double(initialCritical))
        _marginSlider = State(initialValue: Double(initialMargin))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(
                String(localized: "sidebar.themes"),
                subtitle: String(localized: "sidebar.themes.subtitle")
            )

            // Smart Color (global toggle, drives gauges + countdowns coloring)
            glassCard {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            cardLabel(String(localized: "settings.smartcolor.title"))
                            Button {
                                showSmartColorPopover.toggle()
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showSmartColorPopover, arrowEdge: .bottom) {
                                smartColorInfoPopover
                            }
                        }
                        Text(String(localized: "settings.smartcolor.hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $settingsStore.smartColorEnabled)
                        .toggleStyle(.switch)
                        .tint(.blue)
                        .labelsHidden()
                }
            }

            // Presets
            glassCard {
                VStack(alignment: .leading, spacing: 12) {
                    cardLabel(String(localized: "settings.theme.preset"))
                    HStack(spacing: 12) {
                        ForEach(ThemeColors.allPresets, id: \.key) { preset in
                            presetCard(key: preset.key, label: preset.label, colors: preset.colors)
                        }
                        customPresetCard()
                    }
                }
            }

            // Custom colors (if custom selected)
            if themeStore.selectedPreset == "custom" {
                glassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        cardLabel(String(localized: "settings.theme.colors"))
                        themeColorRow("settings.theme.gauge.normal", hex: $themeStore.customTheme.gaugeNormal)
                        themeColorRow("settings.theme.gauge.warning", hex: $themeStore.customTheme.gaugeWarning)
                        themeColorRow("settings.theme.gauge.critical", hex: $themeStore.customTheme.gaugeCritical)
                        themeColorRow("settings.theme.pacing.chill", hex: $themeStore.customTheme.pacingChill)
                        themeColorRow("settings.theme.pacing.ontrack", hex: $themeStore.customTheme.pacingOnTrack)
                        themeColorRow("settings.theme.pacing.hot", hex: $themeStore.customTheme.pacingHot)
                    }
                }
            }

            // Thresholds
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.theme.thresholds"))
                    thresholdSlider(label: String(localized: "settings.theme.warning"), value: $warningSlider, range: 10...90)
                    thresholdSlider(label: String(localized: "settings.theme.critical"), value: $criticalSlider, range: 15...95)

                    // Preview gauges
                    HStack(spacing: 24) {
                        Spacer()
                        themePreviewGauge(pct: Double(max(themeStore.warningThreshold - 15, 5)), label: "Normal")
                        themePreviewGauge(pct: Double(themeStore.warningThreshold + themeStore.criticalThreshold) / 2.0, label: "Warning")
                        themePreviewGauge(pct: Double(min(themeStore.criticalThreshold + 5, 100)), label: "Critical")
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }

            // Pacing margin
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.pacing.margin"))
                    thresholdSlider(label: String(localized: "settings.pacing.margin.value"), value: $marginSlider, range: 5...30)
                    Text(String(localized: "settings.pacing.margin.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            // Reset
            HStack {
                Spacer()
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Text(String(localized: "settings.theme.reset"))
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .alert(String(localized: "settings.theme.reset.confirm"), isPresented: $showResetAlert) {
                    Button(String(localized: "settings.theme.reset.cancel"), role: .cancel) { }
                    Button(String(localized: "settings.theme.reset.action"), role: .destructive) {
                        themeStore.resetToDefaults()
                        // Reset is scoped to the Themes view, so it also clears the
                        // menu-bar text colors displayed on this page.
                        settingsStore.resetTextColorHex = ""
                        settingsStore.sessionPeriodColorHex = ""
                        settingsStore.smartColorEnabled = true
                        themeStore.menuBarMonochrome = false
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .onChange(of: warningSlider) { _, new in
            let int = Int(new)
            if themeStore.warningThreshold != int { themeStore.warningThreshold = int }
            if int >= themeStore.criticalThreshold { themeStore.criticalThreshold = min(int + 5, 95) }
        }
        .onChange(of: criticalSlider) { _, new in
            let int = Int(new)
            if themeStore.criticalThreshold != int { themeStore.criticalThreshold = int }
            if int <= themeStore.warningThreshold { themeStore.warningThreshold = max(int - 5, 10) }
        }
        .onChange(of: marginSlider) { _, new in
            let int = Int(new)
            if settingsStore.pacingMargin != int { settingsStore.pacingMargin = int }
        }
        .onChange(of: themeStore.warningThreshold) { _, new in
            let d = Double(new); if warningSlider != d { warningSlider = d }
        }
        .onChange(of: themeStore.criticalThreshold) { _, new in
            let d = Double(new); if criticalSlider != d { criticalSlider = d }
        }
        .onChange(of: settingsStore.pacingMargin) { _, new in
            let d = Double(new); if marginSlider != d { marginSlider = d }
        }
        .onChange(of: themeStore.selectedPreset) { oldValue, newValue in
            if newValue == "custom", let source = ThemeColors.preset(for: oldValue) {
                themeStore.customTheme = source
            }
        }
    }

    // MARK: - Smart Color popover

    private var smartColorInfoPopover: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Header
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.brandPrimary)
                Text(String(localized: "settings.smartcolor.popover.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
            }

            // Intro
            Text(String(localized: "settings.smartcolor.popover.intro"))
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Divider().opacity(0.18)

            // Example cards
            VStack(spacing: DS.Spacing.sm) {
                smartColorExample(
                    glyph: "leaf.fill",
                    pct: 95,
                    resetText: "2 min",
                    zoneLabel: String(localized: "settings.smartcolor.popover.example1.label"),
                    color: Color(hex: themeStore.current.gaugeNormal),
                    explanation: String(localized: "settings.smartcolor.popover.example1")
                )
                smartColorExample(
                    glyph: "flame.fill",
                    pct: 50,
                    resetText: "5 h",
                    zoneLabel: String(localized: "settings.smartcolor.popover.example2.label"),
                    color: Color(hex: themeStore.current.gaugeCritical),
                    explanation: String(localized: "settings.smartcolor.popover.example2")
                )
            }

            // Formula footer
            Text(String(localized: "settings.smartcolor.popover.formula"))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .italic()
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DS.Spacing.xxs)
        }
        .padding(DS.Spacing.lg)
        .frame(width: 400)
    }

    private func smartColorExample(
        glyph: String,
        pct: Int,
        resetText: String,
        zoneLabel: String,
        color: Color,
        explanation: String
    ) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            // Left column -> glyph + value + reset
            VStack(spacing: 4) {
                Image(systemName: glyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.45), radius: 6)
                Text("\(pct)%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(resetText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .frame(width: 64)

            // Right column -> zone label + explanation
            VStack(alignment: .leading, spacing: 4) {
                Text(zoneLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(color)
                Text(explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(color.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(color.opacity(0.28), lineWidth: 1)
                )
        )
    }

    // MARK: - Preset Card

    private func presetCard(key: String, label: String, colors: ThemeColors) -> some View {
        let isSelected = themeStore.selectedPreset == key
        return Button {
            themeStore.selectedPreset = key
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: colors.gaugeNormal), Color(hex: colors.gaugeWarning), Color(hex: colors.gaugeCritical)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle().stroke(isSelected ? Color.white : .clear, lineWidth: 2)
                    )
                    .shadow(color: isSelected ? Color.white.opacity(0.3) : .clear, radius: 6)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.5))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private func customPresetCard() -> some View {
        let isSelected = themeStore.selectedPreset == "custom"
        return Button {
            themeStore.selectedPreset = "custom"
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(
                        AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center)
                    )
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(isSelected ? Color.white : .clear, lineWidth: 2))
                    .shadow(color: isSelected ? Color.white.opacity(0.3) : .clear, radius: 6)
                Text(String(localized: "settings.theme.custom"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.5))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    // MARK: - Helpers

    private func themeColorRow(_ labelKey: LocalizedStringKey, hex: Binding<String>) -> some View {
        let colorBinding = Binding<Color>(
            get: { Color(hex: hex.wrappedValue) },
            set: { newColor in
                let nsColor = NSColor(newColor).usingColorSpace(.sRGB) ?? NSColor(newColor)
                let r = Int(nsColor.redComponent * 255)
                let g = Int(nsColor.greenComponent * 255)
                let b = Int(nsColor.blueComponent * 255)
                hex.wrappedValue = String(format: "#%02X%02X%02X", r, g, b)
            }
        )
        return HStack {
            Text(labelKey)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
        }
    }

    private func thresholdSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 60, alignment: .leading)
            Slider(value: value, in: range, step: 5)
                .tint(.blue)
            Text("\(Int(value.wrappedValue))%")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func themePreviewGauge(pct: Double, label: String) -> some View {
        let color = themeStore.current.gaugeColor(for: pct, thresholds: themeStore.thresholds)
        return VStack(spacing: 4) {
            RingGauge(
                percentage: Int(pct),
                gradient: themeStore.current.gaugeGradient(for: pct, thresholds: themeStore.thresholds, startPoint: .leading, endPoint: .trailing),
                size: 40,
                glowColor: color,
                glowRadius: 3
            )
            .overlay {
                GlowText(
                    "\(Int(pct))%",
                    font: .system(size: 10, weight: .black, design: .rounded),
                    color: color,
                    glowRadius: 2
                )
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

import SwiftUI

/// Studio editor for the visual theme. Three columns like the popover and
/// menu bar editors: a preset rail on the left, the editing controls in the
/// middle (glow, custom colours, reset), and a live preview on the right that
/// shows the gauge states and pacing zones in the current palette.
struct ThemesSectionView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    /// Local mirror of the glow switch -> avoids a `Binding(get:set:)` on a
    /// computed value (banned: it never memoizes and loops in Release).
    @State private var glowOn = true

    private let horizontalThreshold: CGFloat = 780

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= horizontalThreshold {
                horizontalLayout
            } else {
                verticalLayout
            }
        }
        .onAppear { glowOn = settingsStore.glowIntensity == .glow }
        .onChange(of: glowOn) { _, on in
            settingsStore.glowIntensity = on ? .glow : .flat
        }
        .onChange(of: settingsStore.glowIntensity) { _, mode in
            glowOn = mode == .glow
        }
        .onChange(of: themeStore.selectedPreset) { oldValue, newValue in
            if newValue == "custom", let source = ThemeColors.preset(for: oldValue) {
                themeStore.customTheme = source
            }
        }
    }

    // MARK: - Layouts

    private var horizontalLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            presetRail

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    glowCard
                    if themeStore.selectedPreset == "custom" {
                        customColorsCard
                    }
                    Spacer(minLength: 8)
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 12) {
                editorSectionLabel("theme.preview.title")
                themePreview
                resetButton
                Spacer(minLength: 0)
            }
            .frame(width: 260, alignment: .top)
        }
        .padding(20)
    }

    private var verticalLayout: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                themePreview
                presetStrip
                glowCard
                if themeStore.selectedPreset == "custom" {
                    customColorsCard
                }
                resetButton
            }
            .padding(20)
        }
    }

    // MARK: - Preset rail

    private var presetRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorSectionLabel("settings.theme.preset")
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(ThemeColors.allPresets, id: \.key) { preset in
                        presetCard(
                            key: preset.key,
                            label: preset.label,
                            swatch: AnyShapeStyle(LinearGradient(
                                colors: [
                                    Color(hex: preset.colors.gaugeNormal),
                                    Color(hex: preset.colors.gaugeWarning),
                                    Color(hex: preset.colors.gaugeCritical),
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                        )
                    }
                    presetCard(
                        key: "custom",
                        label: String(localized: "settings.theme.custom"),
                        swatch: AnyShapeStyle(AngularGradient(
                            colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center
                        ))
                    )
                }
                .padding(.vertical, 2)
            }
        }
        .frame(width: 108)
    }

    /// Horizontal preset strip for the narrow fallback.
    private var presetStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorSectionLabel("settings.theme.preset")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ThemeColors.allPresets, id: \.key) { preset in
                        presetCard(
                            key: preset.key,
                            label: preset.label,
                            swatch: AnyShapeStyle(LinearGradient(
                                colors: [
                                    Color(hex: preset.colors.gaugeNormal),
                                    Color(hex: preset.colors.gaugeWarning),
                                    Color(hex: preset.colors.gaugeCritical),
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                        )
                        .frame(width: 100)
                    }
                    presetCard(
                        key: "custom",
                        label: String(localized: "settings.theme.custom"),
                        swatch: AnyShapeStyle(AngularGradient(
                            colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center
                        ))
                    )
                    .frame(width: 100)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func presetCard(key: String, label: String, swatch: AnyShapeStyle) -> some View {
        let isSelected = themeStore.selectedPreset == key
        return Button {
            themeStore.selectedPreset = key
        } label: {
            VStack(spacing: 8) {
                Circle()
                    .fill(swatch)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .dsGlow(color: isSelected ? DS.Palette.accentStudio : .clear, token: DS.Glow.subtle)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.bgPanel.opacity(isSelected ? 0.92 : 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(isSelected ? DS.Palette.accentStudio.opacity(0.5) : DS.Palette.glassBorderLo, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(DS.Motion.springSnap, value: isSelected)
    }

    // MARK: - Middle cards

    private var glowCard: some View {
        glassCard {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    cardLabel(String(localized: "settings.glow.title"))
                    Text(String(localized: "settings.glow.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $glowOn)
                    .toggleStyle(.switch)
                    .tint(DS.Palette.accentStudio)
                    .labelsHidden()
            }
        }
    }

    private var customColorsCard: some View {
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

    private var resetButton: some View {
        StudioResetButton {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                themeStore.resetToDefaults()
                settingsStore.resetTextColorHex = ""
                settingsStore.sessionPeriodColorHex = ""
                themeStore.menuBarMonochrome = false
            }
        }
    }

    // MARK: - Live preview

    private var themePreview: some View {
        let theme = themeStore.current
        let thresholds = themeStore.thresholds
        return VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "theme.preview.gauges"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.4))
            HStack(spacing: 14) {
                miniGauge(pct: 32, color: theme.gaugeColor(for: 32, thresholds: thresholds))
                miniGauge(pct: 71, color: theme.gaugeColor(for: 71, thresholds: thresholds))
                miniGauge(pct: 94, color: theme.gaugeColor(for: 94, thresholds: thresholds))
            }

            Text(String(localized: "theme.preview.pacing"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.4))
            VStack(spacing: 8) {
                pacingRow(color: theme.pacingColor(for: .chill), fraction: 0.35)
                pacingRow(color: theme.pacingColor(for: .onTrack), fraction: 0.55)
                pacingRow(color: theme.pacingColor(for: .warning), fraction: 0.78)
                pacingRow(color: theme.pacingColor(for: .hot), fraction: 0.95)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.bgPanel.opacity(0.92))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
        )
    }

    private func miniGauge(pct: Int, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(pct, 0), 100)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .dsGlow(color, radius: 5, opacity: 0.5)
            Text("\(pct)%")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: 58, height: 58)
    }

    private func pacingRow(color: Color, fraction: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 6)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * fraction, height: 6)
                    .dsGlow(color, radius: 3, opacity: 0.45)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 10)
    }

    // MARK: - Helpers

    private func editorSectionLabel(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .textCase(.uppercase)
            .tracking(0.8)
    }

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
}

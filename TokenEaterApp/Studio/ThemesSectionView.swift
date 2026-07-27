import SwiftUI

struct ThemesSectionView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(
                String(localized: "sidebar.themes"),
                subtitle: String(localized: "sidebar.themes.subtitle")
            )

            // Glow intensity
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
                    Toggle("", isOn: Binding(
                        get: { settingsStore.glowIntensity == .glow },
                        set: { settingsStore.glowIntensity = $0 ? .glow : .flat }
                    ))
                    .toggleStyle(.switch)
                    .tint(DS.Palette.accentSettings)
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

            // Reset
            ResetSectionButton(
                confirmTitle: String(localized: "settings.theme.reset.confirm")
            ) {
                themeStore.resetToDefaults()
                // Scoped to the Themes view: also clears the menu-bar text
                // colors displayed elsewhere. Smart Color / pacing live in their
                // own section now, so they are not touched here.
                settingsStore.resetTextColorHex = ""
                settingsStore.sessionPeriodColorHex = ""
                themeStore.menuBarMonochrome = false
            }

            Spacer()
        }
        .padding(24)
        .onChange(of: themeStore.selectedPreset) { oldValue, newValue in
            if newValue == "custom", let source = ThemeColors.preset(for: oldValue) {
                themeStore.customTheme = source
            }
        }
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
}

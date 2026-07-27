import SwiftUI

struct DisplaySectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var usageStore: UsageStore

    var body: some View {
        // The menu bar editor owns the three-column Studio layout; this view
        // injects the show/hide toggle above the live preview and the colour
        // controls + reset below it (the preview is short, so its column has
        // the room).
        MenuBarEditorView(
            previewHeader: {
                ClickChip(
                    label: String(localized: "settings.menubar.toggle"),
                    icon: settingsStore.showMenuBar ? "checkmark" : "eye.slash",
                    isActive: settingsStore.showMenuBar,
                    accent: .blue,
                    style: .compact
                ) {
                    settingsStore.showMenuBar.toggle()
                }
            },
            previewFooter: {
                colorsGroup
                ResetSectionButton(
                    confirmTitle: String(localized: "settings.display.reset.confirm")
                ) {
                    resetDisplayDefaults()
                }
            }
        )
    }

    // MARK: - Colors group

    /// Global menu bar colour mode (monochrome vs theme palette) plus the two
    /// hex overrides. These stay global - the composable segments carry layout,
    /// not colour; colour still comes from the theme / smart-colour system.
    private var colorsGroup: some View {
        groupSection(title: "settings.group.colors", subtitle: "settings.group.colors.hint") {
            VStack(alignment: .leading, spacing: 12) {
                // Mono / Custom radio pair -> single tap to switch theme.
                HStack(spacing: 8) {
                    BinaryChoiceChip(
                        label: String(localized: "settings.theme.color.custom"),
                        icon: "paintpalette.fill",
                        isActive: !themeStore.menuBarMonochrome
                    ) {
                        themeStore.menuBarMonochrome = false
                    }
                    BinaryChoiceChip(
                        label: String(localized: "settings.theme.color.mono"),
                        icon: "circle.lefthalf.filled.inverse",
                        isActive: themeStore.menuBarMonochrome
                    ) {
                        themeStore.menuBarMonochrome = true
                    }
                }

                Divider().opacity(0.12)
                // Reset-countdown colour is non-monochrome only (in monochrome
                // it is driven by the system label / smart colour).
                if !themeStore.menuBarMonochrome {
                    menuBarColorRow(
                        label: "settings.reset.color",
                        hex: $settingsStore.display.resetTextColorHex,
                        fallback: .white,
                        disabled: settingsStore.smartColorEnabled
                    )
                }
                // Period-label ("5h" / "7d") colour is tweakable in BOTH modes,
                // including monochrome, so a light-menu-bar user can fix its
                // legibility (#196). The swatch mirrors the secondary (~55%)
                // default in MenuBarRenderer.defaultPeriodLabelColor.
                menuBarColorRow(
                    label: "settings.session.periodcolor",
                    hex: $settingsStore.display.sessionPeriodColorHex,
                    fallback: .white.opacity(0.55),
                    disabled: false
                )
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: themeStore.menuBarMonochrome)
        }
    }

    // MARK: - Group scaffolding

    @ViewBuilder
    private func groupSection<Content: View>(title: String.LocalizationValue, subtitle: String.LocalizationValue, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: title).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.55))
                Text(String(localized: subtitle))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )
        )
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

    /// Reset the menu bar to the Classic composition and clear the colour
    /// overrides. Monochrome lives in ThemeStore and is reset separately by
    /// the Themes section.
    private func resetDisplayDefaults() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            settingsStore.menuBarComposition = MenuBarBuiltinTemplate.classic.composition
        }
        settingsStore.resetTextColorHex = ""
        settingsStore.sessionPeriodColorHex = ""
    }
}

// MARK: - Chip components

/// Generic click-to-toggle chip. Two visual styles:
/// - `.compact`  -> short pill for header / inline use
/// - `.tile`     -> larger card-like surface for grouped grids
struct ClickChip: View {
    enum Style { case compact, tile }

    let label: String
    let icon: String?
    let isActive: Bool
    let accent: Color
    var style: Style = .tile
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: style == .compact ? 5 : 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: style == .compact ? 9 : 11, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: style == .compact ? 10 : 12, weight: .medium))
            }
            .foregroundStyle(isActive ? accent : .white.opacity(0.55))
            .padding(.horizontal, style == .compact ? 9 : 12)
            .padding(.vertical, style == .compact ? 5 : 8)
            .frame(maxWidth: style == .tile ? .infinity : nil)
            .background(chipBackground)
            .scaleEffect(hovering ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hovering)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var chipBackground: some View {
        let radius: CGFloat = style == .compact ? 7 : 9
        RoundedRectangle(cornerRadius: radius)
            .fill(isActive ? accent.opacity(0.18) : Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(isActive ? accent.opacity(0.55) : Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

/// Radio-style chip for binary choices (e.g., monochrome vs custom colors).
/// Different from ClickChip because it expects to live in a sibling pair
/// where exactly one is active.
struct BinaryChoiceChip: View {
    let label: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isActive ? .white : .white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isActive ? Color.blue.opacity(0.18) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(isActive ? Color.blue.opacity(0.45) : Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
            .scaleEffect(hovering ? 1.01 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

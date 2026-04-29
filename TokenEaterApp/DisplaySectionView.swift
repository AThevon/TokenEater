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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    sectionTitle(
                        String(localized: "sidebar.display"),
                        subtitle: String(localized: "sidebar.display.subtitle")
                    )
                    Spacer()
                    ClickChip(
                        label: String(localized: "settings.menubar.toggle"),
                        icon: settingsStore.showMenuBar ? "checkmark" : "eye.slash",
                        isActive: settingsStore.showMenuBar,
                        accent: .blue,
                        style: .compact
                    ) {
                        settingsStore.showMenuBar.toggle()
                    }
                }

                chromeGroup
                pinGroup
                colorsGroup

                ResetSectionButton(
                    confirmTitle: String(localized: "settings.display.reset.confirm")
                ) {
                    resetDisplayDefaults()
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
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

    // MARK: - Chrome group

    private var chromeGroup: some View {
        groupSection(title: "settings.group.chrome", subtitle: "settings.group.chrome.hint") {
            VStack(alignment: .leading, spacing: 12) {
                groupLabel("settings.menubar.style")
                HStack(spacing: 8) {
                    ForEach(MenuBarStyle.allCases) { style in
                        menuBarStyleButton(style)
                    }
                }

                groupLabel("settings.pacing.shape")
                    .padding(.top, 4)
                HStack(spacing: 8) {
                    ForEach(PacingShape.allCases) { shape in
                        pacingShapeButton(shape)
                    }
                }
            }
        }
    }

    // MARK: - Pin group

    private var pinGroup: some View {
        groupSection(title: "settings.group.pin", subtitle: "settings.group.pin.hint") {
            VStack(alignment: .leading, spacing: 10) {
                // Lane 1 : simple metric pins, no sub-options. 2-column compact grid.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    MetricPinChip(
                        label: String(localized: "metric.session"),
                        icon: "bolt.fill",
                        isActive: showFiveHour,
                        accent: .orange
                    ) { showFiveHour.toggle() }

                    MetricPinChip(
                        label: String(localized: "metric.weekly"),
                        icon: "calendar",
                        isActive: showSevenDay,
                        accent: .blue
                    ) { showSevenDay.toggle() }

                    MetricPinChip(
                        label: String(localized: "metric.sonnet"),
                        icon: "quote.opening",
                        isActive: showSonnet,
                        accent: .green
                    ) { showSonnet.toggle() }

                    if usageStore.hasDesign {
                        MetricPinChip(
                            label: String(localized: "metric.design"),
                            icon: "paintbrush.pointed.fill",
                            isActive: showDesign,
                            accent: .purple
                        ) { showDesign.toggle() }
                    }
                }

                // Lane 2 : pins that carry secondary options. Full-width rows
                // so the option picker sits comfortably to the right of the
                // chip without overlapping the next pin.
                expandingPinRow(
                    label: String(localized: "metric.sessionReset"),
                    icon: "clock.arrow.circlepath",
                    isActive: showSessionReset,
                    accent: .cyan,
                    onToggle: { showSessionReset.toggle() }
                ) {
                    HStack(spacing: 6) {
                        Text(String(localized: "settings.metric.format"))
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(.white.opacity(0.45))
                        ResetFormatPicker(selection: $settingsStore.resetDisplayFormat)
                            .labelsHidden()
                            .frame(maxWidth: 170)
                    }
                }

                expandingPinRow(
                    label: String(localized: "pacing.session.label"),
                    icon: "speedometer",
                    isActive: showSessionPacing,
                    accent: .pink,
                    onToggle: { showSessionPacing.toggle() }
                ) {
                    PacingDisplayPicker(selection: $settingsStore.sessionPacingDisplayMode)
                        .labelsHidden()
                }

                expandingPinRow(
                    label: String(localized: "pacing.weekly.label"),
                    icon: "speedometer",
                    isActive: showWeeklyPacing,
                    accent: .pink,
                    onToggle: { showWeeklyPacing.toggle() }
                ) {
                    PacingDisplayPicker(selection: $settingsStore.weeklyPacingDisplayMode)
                        .labelsHidden()
                }
            }
        }
    }

    /// Full-width pin row with the chip on the left and its option picker on
    /// the right. Picker is rendered as a faint inset that lights up when the
    /// chip is active. Avoids the staircase effect we'd get if the picker
    /// hung below in a 2-col grid.
    @ViewBuilder
    private func expandingPinRow<Picker: View>(
        label: String,
        icon: String,
        isActive: Bool,
        accent: Color,
        onToggle: @escaping () -> Void,
        @ViewBuilder picker: () -> Picker
    ) -> some View {
        HStack(spacing: 10) {
            MetricPinChip(label: label, icon: icon, isActive: isActive, accent: accent, action: onToggle)
                .frame(maxWidth: .infinity, alignment: .leading)
            picker()
                .opacity(isActive ? 1 : 0.35)
                .allowsHitTesting(isActive)
                .layoutPriority(1)
        }
    }

    // MARK: - Colors group

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

                if !themeStore.menuBarMonochrome {
                    Divider().opacity(0.12)
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

    private func groupLabel(_ key: String.LocalizationValue) -> some View {
        Text(String(localized: key))
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.45))
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

    private func resetDisplayDefaults() {
        // Pinned metrics: bring back the canonical "session + weekly + session pacing" combo.
        settingsStore.pinnedMetrics = [.fiveHour, .sevenDay, .sessionPacing]
        settingsStore.menuBarStyle = .classic
        settingsStore.pacingShape = .circle
        settingsStore.sessionPacingDisplayMode = .dotDelta
        settingsStore.weeklyPacingDisplayMode = .dotDelta
        settingsStore.resetDisplayFormat = .relative
        settingsStore.resetTextColorHex = ""
        settingsStore.sessionPeriodColorHex = ""
        settingsStore.displaySonnet = true
        settingsStore.displayDesign = true
        // Local @State mirrors so the toggle UI reflects the reset immediately.
        showFiveHour = settingsStore.pinnedMetrics.contains(.fiveHour)
        showSessionReset = settingsStore.pinnedMetrics.contains(.sessionReset)
        showSessionPacing = settingsStore.pinnedMetrics.contains(.sessionPacing)
        showSevenDay = settingsStore.pinnedMetrics.contains(.sevenDay)
        showSonnet = settingsStore.pinnedMetrics.contains(.sonnet)
        showWeeklyPacing = settingsStore.pinnedMetrics.contains(.weeklyPacing)
        showDesign = settingsStore.pinnedMetrics.contains(.design)
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

/// Pin chip for the "What to pin" group. Single-action click target; subsidiary
/// option pickers live as siblings (see `expandingPinRow` in DisplaySectionView)
/// rather than embedded children, which avoids the staircase effect a
/// per-cell expansion would create inside a LazyVGrid.
struct MetricPinChip: View {
    let label: String
    let icon: String
    let isActive: Bool
    let accent: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isActive ? accent : .white.opacity(0.5))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.65))
                Spacer(minLength: 0)
                Image(systemName: isActive ? "checkmark" : "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isActive ? accent : .white.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? accent.opacity(0.14) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isActive ? accent.opacity(0.5) : Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
            .scaleEffect(hovering ? 1.01 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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


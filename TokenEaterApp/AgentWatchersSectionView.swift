import SwiftUI

struct AgentWatchersSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var sessionStore: SessionStore

    @State private var showTerminalSetup = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    sectionTitle(
                        String(localized: "sidebar.agentWatchers"),
                        subtitle: String(localized: "sidebar.agentWatchers.subtitle")
                    )
                    Spacer()
                    ClickChip(
                        label: String(localized: "settings.overlay.toggle"),
                        icon: settingsStore.overlayEnabled ? "checkmark" : "eye.slash",
                        isActive: settingsStore.overlayEnabled,
                        accent: .blue,
                        style: .compact
                    ) {
                        settingsStore.overlayEnabled.toggle()
                    }
                }

                styleGroup
                behaviorGroup
                legendGroup
                terminalSetupRow

                ResetSectionButton(
                    confirmTitle: String(localized: "settings.watchers.reset.confirm")
                ) {
                    resetWatcherDefaults()
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .sheet(isPresented: $showTerminalSetup) {
            TerminalSetupSheet(isPresented: $showTerminalSetup)
        }
    }

    // MARK: - Style group

    private var styleGroup: some View {
        groupSection(title: "settings.watchers.style", subtitle: "settings.watchers.style.hint") {
            HStack(spacing: 12) {
                stylePreviewCard(.frost)
                stylePreviewCard(.neon)
            }
        }
    }

    // MARK: - Behavior group

    private var behaviorGroup: some View {
        groupSection(title: "settings.watchers.behavior", subtitle: "settings.watchers.behavior.hint") {
            VStack(alignment: .leading, spacing: 14) {
                // Display mode -> chip pair
                groupLabel("settings.watchers.display")
                HStack(spacing: 8) {
                    ForEach(WatcherDisplayMode.allCases, id: \.self) { mode in
                        BinaryChoiceChip(
                            label: mode.label,
                            icon: mode == .branchPriority ? "arrow.triangle.branch" : "folder.fill",
                            isActive: settingsStore.watcherDisplayMode == mode
                        ) {
                            settingsStore.watcherDisplayMode = mode
                        }
                    }
                }

                // Trigger zone -> 4 chips
                groupLabel("settings.watchers.trigger")
                    .padding(.top, 4)
                HStack(spacing: 6) {
                    ForEach(OverlayTriggerZone.allCases) { zone in
                        BinaryChoiceChip(
                            label: zone.localizedLabel,
                            icon: triggerIcon(zone),
                            isActive: settingsStore.overlayTriggerZone == zone
                        ) {
                            settingsStore.overlayTriggerZone = zone
                        }
                    }
                }

                // Side + dock effect + animations -> chip row
                HStack(spacing: 8) {
                    ClickChip(
                        label: String(localized: "settings.watchers.dock"),
                        icon: "arrow.down.left.arrow.up.right.square",
                        isActive: settingsStore.overlayDockEffect,
                        accent: .blue
                    ) {
                        settingsStore.overlayDockEffect.toggle()
                    }
                    ClickChip(
                        label: String(localized: "settings.watchers.leftside"),
                        icon: "rectangle.lefthalf.filled",
                        isActive: settingsStore.overlayLeftSide,
                        accent: .blue
                    ) {
                        settingsStore.overlayLeftSide.toggle()
                    }
                    ClickChip(
                        label: String(localized: "settings.watchers.animations"),
                        icon: "wand.and.sparkles",
                        isActive: settingsStore.watcherAnimationsEnabled,
                        accent: .blue
                    ) {
                        settingsStore.watcherAnimationsEnabled.toggle()
                    }
                }
                .padding(.top, 4)

                // Size slider with reset hint
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        groupLabel("settings.watchers.size")
                        Spacer()
                        Text("\(Int(settingsStore.overlayScale * 100))%")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .monospacedDigit()
                        if abs(settingsStore.overlayScale - 1.1) > 0.01 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    settingsStore.overlayScale = 1.1
                                }
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .help(Text(String(localized: "settings.watchers.size.reset")))
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "minus")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                        Slider(value: $settingsStore.overlayScale, in: 0.6...1.6, step: 0.05)
                            .tint(.blue)
                        Image(systemName: "plus")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func triggerIcon(_ zone: OverlayTriggerZone) -> String {
        switch zone {
        case .minimal: return "rectangle.compress.vertical"
        case .narrow:  return "rectangle.center.inset.filled"
        case .medium:  return "square.split.bottomrightquarter"
        case .wide:    return "rectangle.expand.vertical"
        }
    }

    // MARK: - Legend group

    private var legendGroup: some View {
        groupSection(title: "settings.watchers.legend", subtitle: "settings.watchers.legend.hint") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    BinaryChoiceChip(
                        label: String(localized: "settings.watchers.legend.simple"),
                        icon: "circle.lefthalf.filled",
                        isActive: !settingsStore.watchersDetailedMode
                    ) {
                        settingsStore.watchersDetailedMode = false
                    }
                    BinaryChoiceChip(
                        label: String(localized: "settings.watchers.legend.detailed"),
                        icon: "circle.hexagongrid.fill",
                        isActive: settingsStore.watchersDetailedMode
                    ) {
                        settingsStore.watchersDetailedMode = true
                    }
                }

                Divider().opacity(0.12)

                if settingsStore.watchersDetailedMode {
                    statusRow(color: Color(red: 0.3, green: 0.78, blue: 0.52), label: String(localized: "settings.watchers.idle"))
                    statusRow(color: Color(red: 0.95, green: 0.62, blue: 0.22), label: String(localized: "settings.watchers.thinking"))
                    statusRow(color: Color(red: 0.38, green: 0.58, blue: 0.95), label: String(localized: "settings.watchers.executing"))
                    statusRow(color: Color(red: 0.7, green: 0.45, blue: 0.95), label: String(localized: "settings.watchers.waiting"))
                    statusRow(color: Color(red: 0.25, green: 0.85, blue: 0.85), label: String(localized: "settings.watchers.subagent"))
                    statusRow(color: Color(red: 0.55, green: 0.55, blue: 0.60), label: String(localized: "settings.watchers.compacting"))
                } else {
                    statusRow(color: Color(red: 0.3, green: 0.78, blue: 0.52), label: String(localized: "settings.watchers.simple.idle"))
                    statusRow(color: Color(red: 0.95, green: 0.62, blue: 0.22), label: String(localized: "settings.watchers.simple.working"))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: settingsStore.watchersDetailedMode)
        }
    }

    // MARK: - Terminal setup row

    private var terminalSetupRow: some View {
        Button {
            showTerminalSetup = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.watchers.terminalSetup"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(String(localized: "settings.watchers.terminalSetup.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Group helpers

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

    private func resetWatcherDefaults() {
        settingsStore.overlayEnabled = true
        settingsStore.overlayDockEffect = true
        settingsStore.overlayScale = 1.1
        settingsStore.overlayLeftSide = false
        settingsStore.overlayTriggerZone = .medium
        settingsStore.watchersDetailedMode = true
        settingsStore.watcherStyle = .frost
        settingsStore.watcherDisplayMode = .branchPriority
        settingsStore.watcherAnimationsEnabled = true
    }

    // MARK: - Style preview cards

    /// Realistic mini-tile demonstration of each WatcherStyle. Click anywhere
    /// on the card to select. The fake tile shows a project name + branch +
    /// status dot rendered in the actual style chrome so the difference is
    /// readable at a glance.
    private func stylePreviewCard(_ style: WatcherStyle) -> some View {
        let isSelected = settingsStore.watcherStyle == style
        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                settingsStore.watcherStyle = style
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                WatcherTilePreview(style: style)
                    .frame(maxWidth: .infinity)

                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? .blue : .white.opacity(0.3))
                    Text(style.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
            .scaleEffect(isSelected ? 1.0 : 0.99)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status legend row

    private func statusRow(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            statusIndicator(color: color)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    @ViewBuilder
    private func statusIndicator(color: Color) -> some View {
        switch settingsStore.watcherStyle {
        case .frost:
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 12)
        case .neon:
            let neonVariant = color
            RoundedRectangle(cornerRadius: 2)
                .fill(.black.opacity(0.6))
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(neonVariant.opacity(0.8), lineWidth: 1.5)
                )
                .shadow(color: neonVariant.opacity(0.4), radius: 3)
        }
    }
}

// MARK: - Terminal setup sheet

/// Modal that gathers all per-terminal helpers (tmux / wezterm / kitty) under
/// a single tabbed sheet so the main settings page doesn't carry three almost-
/// identical card blocks. Each tab shows a short description, the snippet to
/// drop in the user's config, and a copy button.
private struct TerminalSetupSheet: View {
    @Binding var isPresented: Bool

    enum Tab: String, CaseIterable, Identifiable {
        case tmux, wezterm, kitty
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .tmux:    return "tmux"
            case .wezterm: return "WezTerm"
            case .kitty:   return "Kitty"
            }
        }

        var icon: String {
            switch self {
            case .tmux:    return "rectangle.split.3x1"
            case .wezterm: return "rectangle.grid.2x2"
            case .kitty:   return "pawprint.fill"
            }
        }
    }

    @State private var activeTab: Tab = .tmux
    @State private var copied: Tab? = nil

    private let tmuxSnippet = """
    set-option -g update-environment "TERM_PROGRAM"
    """
    private let weztermSnippet = """
    wezterm.on('gui-startup', function()
      local script = os.getenv('HOME') .. '/Library/Application Support/com.tokeneater.shared/wezterm-watcher.sh'
      local f = io.open(script, 'r')
      if f then f:close(); io.popen('nohup bash "' .. script .. '" >/dev/null 2>&1 &') end
    end)
    """
    private let kittySnippet = "allow_remote_control yes"

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 8) {
                ForEach(Tab.allCases) { tab in
                    BinaryChoiceChip(
                        label: tab.displayName,
                        icon: tab.icon,
                        isActive: activeTab == tab
                    ) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            activeTab = tab
                            copied = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            content
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
        }
        .frame(width: 520)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.55))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.watchers.terminalSetup"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(String(localized: "settings.watchers.terminalSetup.sheet.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: hintKey))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                Text(activeSnippet)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    // Pin the snippet container to the height of the longest
                    // snippet (wezterm, ~5 lines). Switching tabs no longer
                    // changes the sheet height, so tab hit-targets stay put.
                    .frame(minHeight: 110, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.black.opacity(0.45))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.06), lineWidth: 1)
                            )
                    )
                    .textSelection(.enabled)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(activeSnippet.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
                    copied = activeTab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copied == activeTab { copied = nil }
                    }
                } label: {
                    Image(systemName: copied == activeTab ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var activeSnippet: String {
        switch activeTab {
        case .tmux:    return tmuxSnippet
        case .wezterm: return weztermSnippet
        case .kitty:   return kittySnippet
        }
    }

    private var hintKey: String.LocalizationValue {
        switch activeTab {
        case .tmux:    return "settings.watchers.tmux.hint"
        case .wezterm: return "settings.watchers.wezterm.hint"
        case .kitty:   return "settings.watchers.kitty.hint"
        }
    }
}

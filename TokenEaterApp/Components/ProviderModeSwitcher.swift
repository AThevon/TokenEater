import SwiftUI

/// The All / per-provider selector.
///
/// One live mode for the whole app, so this control and the one in the popover
/// drive the same `activeProviderMode`. That is what makes editing safe: an
/// editor can never be showing a mode the app is not currently in.
///
/// Hidden below two active providers: with Claude alone, All and Claude
/// describe the same thing and there is nothing to choose, so a user who never
/// enables OpenAI sees no new chrome at all. That gate reads
/// `availableProviderModes`, which follows the Providers toggles in Settings,
/// so turning a provider off removes its mode too.
struct ProviderModeSwitcher: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    enum Size {
        /// Matches `TopPillsNav` exactly: same 12pt medium label, same
        /// horizontal and vertical padding, same container inset. This control
        /// sits on the same row as those tabs, and being two points smaller
        /// than its neighbour read as an afterthought rather than as app-level
        /// chrome.
        case regular
        /// Three dots, no words. For the popover, where 300 points of width
        /// are already spoken for and the pills would eat a whole row to say
        /// something the glyphs say on their own.
        case dots

        var font: CGFloat {
            switch self { case .dots: 11; case .regular: 12 }
        }
        var horizontalPadding: CGFloat {
            switch self { case .dots: 7; case .regular: DS.Spacing.md }
        }
        var verticalPadding: CGFloat {
            switch self { case .dots: 5; case .regular: 7 }
        }
        var containerPadding: CGFloat {
            switch self { case .dots: 3; case .regular: DS.Spacing.xxs }
        }
        var showsLabel: Bool { self != .dots }
    }

    var size: Size = .regular
    /// The caption naming what the mode hides.
    ///
    /// Off in the window bar: a line that appears and disappears under the
    /// pills shifts the whole row every time the mode changes, and a sentence
    /// you read once becomes noise on a control you use every day. The
    /// Coverage page in Settings is where that answer lives; the what's-new
    /// step is where it is worth saying out loud.
    var showsCaption: Bool = false

    private var modes: [ProviderMode] { settingsStore.availableProviderModes }

    var body: some View {
        if modes.count > 1 {
            if showsCaption {
                VStack(alignment: .trailing, spacing: 6) {
                    pills
                    caption
                }
            } else {
                // No wrapper when there is no caption, so the control centres
                // on its row instead of sitting high in a two-row stack.
                pills
            }
        }
    }

    private var pills: some View {
        HStack(spacing: 4) {
            ForEach(modes) { mode in
                pill(mode)
            }
        }
        .padding(size.containerPadding)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }

    private func pill(_ mode: ProviderMode) -> some View {
        let isActive = settingsStore.activeProviderMode == mode
        return Button {
            guard !isActive else { return }
            settingsStore.activeProviderMode = mode
        } label: {
            HStack(spacing: 4) {
                if let provider = mode.provider {
                    ProviderGlyph(provider: provider, size: size.font + 2)
                } else if !size.showsLabel {
                    // "All" has no mark of its own, so in the wordless variant
                    // it becomes the one thing that is not a provider mark:
                    // a filled dot standing for every provider at once.
                    Circle()
                        .fill(isActive ? DS.Palette.bgElevated : DS.Palette.textSecondary)
                        .frame(width: size.font - 1, height: size.font - 1)
                }
                if size.showsLabel {
                    Text(mode.localizedLabel)
                }
            }
            .font(.system(size: size.font, weight: isActive ? .semibold : .medium))
            // The active pill used to be a 12% white wash and a semibold
            // weight, which at this size is not a state, it is a suggestion.
            // Knowing which mode you are in is the whole job of this control.
            .foregroundStyle(isActive ? DS.Palette.bgElevated : DS.Palette.textSecondary)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(
                Capsule().fill(isActive ? DS.Palette.textPrimary.opacity(0.92) : .clear)
            )
            // A clear fill is not hit-testable, so an inactive pill only
            // answered to a click that landed exactly on its text.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // The tooltip used to repeat the pill's own label, which answers the
        // one question the control raises: what does this change? Naming the
        // surfaces is the answer, and it is the same answer in every mode.
        .help(helpText(for: mode))
        .accessibilityLabel(mode.localizedLabel)
        .accessibilityHint(helpText(for: mode))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// Named after the pill it sits on. The provider's display name reads
    /// "OpenAI" while the pill reads "Codex", and a tooltip that disagrees with
    /// its own control is exactly the confusion it is there to clear up.
    private func helpText(for mode: ProviderMode) -> String {
        guard mode.provider != nil else { return String(localized: "mode.help.all") }
        return String(format: String(localized: "mode.help.one"), mode.localizedLabel)
    }

    /// Names the cost of the current mode where the choice was made.
    ///
    /// Without it, switching to a provider mode silently removes Agent
    /// Watchers, the per-model grid and the outage pill, and the user is left
    /// to discover an empty panel later and wonder whether the app broke.
    @ViewBuilder
    private var caption: some View {
        let hidden = settingsStore.activeProviderMode.unavailableCapabilities
        if let provider = settingsStore.activeProviderMode.provider, !hidden.isEmpty {
            HStack(spacing: 5) {
                Text(String(
                    format: String(localized: hidden.count == 1
                                   ? "mode.caption.one" : "mode.caption.hiding"),
                    provider.displayName, hidden.count
                ))
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.textTertiary)
            }
            .lineLimit(1)
            .transition(.opacity)
        }
    }
}

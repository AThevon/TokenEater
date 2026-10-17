import SwiftUI

/// The All / per-provider selector, with one pill per running Claude account.
///
/// One live mode for the whole app, so this control and the one in the popover
/// drive the same `activeProviderMode` (and, for Claude, the same focused
/// account). That is what makes editing safe: an editor can never be showing
/// a scope the app is not currently in.
///
/// Hidden below two choices: with Claude alone and one account, All and
/// Claude describe the same thing and there is nothing to choose, so a user
/// who never enables OpenAI nor adds an account sees no new chrome at all.
/// That gate reads `modeChoices`, which follows the Providers toggles and the
/// accounts in Settings, so turning a provider off or pausing an account
/// removes its pill too.
///
/// Each Claude account keeps the Claude mark and adds its colour dot, the
/// same identity mark it wears everywhere else. From three running accounts
/// they fold into a single Claude pill that lists them, so the control still
/// fits the 300-point popover.
struct ProviderModeSwitcher: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    enum Size {
        /// Matches `TopPillsNav` exactly: same 12pt medium label, same
        /// horizontal and vertical padding, same container inset. This control
        /// sits on the same row as those tabs, and being two points smaller
        /// than its neighbour read as an afterthought rather than as app-level
        /// chrome.
        case regular
        /// Marks and dots, no words. For the popover, where 300 points of
        /// width are already spoken for and the pills would eat a whole row to
        /// say something the glyphs say on their own.
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
        /// The account dot, a little smaller than the provider mark it sits
        /// next to so the two read as one pill rather than two symbols.
        var dot: CGFloat { font - 4 }
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

    private var choices: [ModeChoice] { settingsStore.modeChoices }

    /// What the row draws: the choices, with the Claude accounts folded into
    /// one menu pill at the place of the first once there are three of them.
    private var entries: [Entry] {
        guard ModeChoice.collapsesClaude(choices) else { return choices.map(Entry.choice) }
        var result: [Entry] = []
        for choice in choices {
            if choice.mode == .claude {
                if !result.contains(.claudeMenu) { result.append(.claudeMenu) }
            } else {
                result.append(.choice(choice))
            }
        }
        return result
    }

    private enum Entry: Hashable, Identifiable {
        case choice(ModeChoice)
        case claudeMenu

        var id: String {
            switch self {
            case .choice(let choice): return choice.id
            case .claudeMenu: return "claude.menu"
            }
        }
    }

    var body: some View {
        if choices.count > 1 {
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
            ForEach(entries) { entry in
                switch entry {
                case .choice(let choice):
                    pill(choice)
                case .claudeMenu:
                    ClaudeAccountsMenuPill(size: size)
                }
            }
        }
        .padding(size.containerPadding)
        .background(Capsule().fill(Color.white.opacity(0.05)))
    }

    private func pill(_ choice: ModeChoice) -> some View {
        let isActive = settingsStore.isSelected(choice)
        let account = accountMark(for: choice)
        return Button {
            guard !isActive else { return }
            settingsStore.selectScope(choice.mode, account: choice.account ?? .main)
        } label: {
            HStack(spacing: 4) {
                if let provider = choice.mode.provider {
                    ProviderGlyph(provider: provider, size: size.font + 2)
                } else if !size.showsLabel {
                    // "All" has no mark of its own, so in the wordless variant
                    // it becomes the one thing that is not a provider mark:
                    // a filled dot standing for every provider at once.
                    Circle()
                        .fill(isActive ? DS.Palette.bgElevated : DS.Palette.textSecondary)
                        .frame(width: size.font - 1, height: size.font - 1)
                }
                if let account {
                    AccountDot(colorHex: account.colorHex, size: size.dot)
                    if size.showsLabel {
                        Text(account.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else if size.showsLabel {
                    Text(choice.mode.localizedLabel)
                }
            }
            .modifier(ModePillChrome(size: size, isActive: isActive))
        }
        .buttonStyle(.plain)
        // The tooltip used to repeat the pill's own label, which answers the
        // one question the control raises: what does this change? Naming the
        // surfaces is the answer, and it is the same answer in every mode.
        .help(helpText(for: choice, account: account))
        .accessibilityLabel(account?.name ?? choice.mode.localizedLabel)
        .accessibilityHint(helpText(for: choice, account: account))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// The account a Claude pill stands for, once the pills need telling
    /// apart. With a single running account the pill is the plain Claude one
    /// it has always been.
    private func accountMark(for choice: ModeChoice) -> ClaudeAccountSummary? {
        guard settingsStore.showsAccountMarkers, let id = choice.account else { return nil }
        return settingsStore.claudeAccount(id)
    }

    /// Named after the pill it sits on. The provider's display name reads
    /// "OpenAI" while the pill reads "Codex", and a tooltip that disagrees with
    /// its own control is exactly the confusion it is there to clear up.
    private func helpText(for choice: ModeChoice, account: ClaudeAccountSummary?) -> String {
        guard choice.mode.provider != nil else { return String(localized: "mode.help.all") }
        return String(format: String(localized: "mode.help.one"), account?.name ?? choice.mode.localizedLabel)
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

/// The look every pill of the switcher shares, so the Claude menu pill
/// cannot drift from the plain ones next to it.
private struct ModePillChrome: ViewModifier {
    let size: ProviderModeSwitcher.Size
    let isActive: Bool

    func body(content: Content) -> some View {
        content
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
}

/// The Claude pill once three or more Claude accounts are running: one pill
/// that lists them, instead of a row of names that no longer fits.
///
/// A popover rather than a `Menu`: a menu draws its items through AppKit,
/// which keeps the text and drops the account's colour dot, and the dot is
/// the one thing that tells the entries apart at a glance.
private struct ClaudeAccountsMenuPill: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    let size: ProviderModeSwitcher.Size

    @State private var showsList = false

    private var isActive: Bool { settingsStore.activeProviderMode == .claude }

    private var focused: ClaudeAccountSummary? {
        settingsStore.claudeAccount(settingsStore.focusedClaudeAccount)
    }

    var body: some View {
        Button {
            showsList.toggle()
        } label: {
            HStack(spacing: 4) {
                ProviderGlyph(provider: .claude, size: size.font + 2)
                if isActive, let focused {
                    AccountDot(colorHex: focused.colorHex, size: size.dot)
                    if size.showsLabel {
                        Text(focused.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else if size.showsLabel {
                    Text(ProviderMode.claude.localizedLabel)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: size.font - 4, weight: .bold))
                    .opacity(0.7)
            }
            .modifier(ModePillChrome(size: size, isActive: isActive))
        }
        .buttonStyle(.plain)
        .help(String(localized: "mode.claudeMenu.help"))
        .accessibilityLabel(isActive ? (focused?.name ?? ProviderMode.claude.localizedLabel) : ProviderMode.claude.localizedLabel)
        .accessibilityHint(String(localized: "mode.claudeMenu.help"))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .popover(isPresented: $showsList, arrowEdge: .bottom) {
            accountList
        }
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("mode.claudeMenu.title")
                .font(DS.Typography.micro)
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(DS.Palette.textTertiary)
                .padding(.horizontal, DS.Spacing.xs)
                .padding(.bottom, 2)
            ForEach(settingsStore.activeClaudeAccounts) { account in
                AccountListRow(
                    account: account,
                    isSelected: settingsStore.isSelected(ModeChoice(mode: .claude, account: account.id))
                ) {
                    settingsStore.selectScope(.claude, account: account.id)
                    showsList = false
                }
            }
        }
        .padding(DS.Spacing.xs)
        .frame(width: 200)
    }
}

/// One account in the Claude menu pill's list: its dot, its full name, a
/// check on the one Claude mode shows.
private struct AccountListRow: View {
    let account: ClaudeAccountSummary
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                ProviderGlyph(provider: .claude, size: 11)
                    .foregroundStyle(DS.Palette.textTertiary)
                AccountDot(colorHex: account.colorHex, size: 8)
                Text(account.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: DS.Spacing.xs)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(isHovering ? Color.white.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(account.name)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

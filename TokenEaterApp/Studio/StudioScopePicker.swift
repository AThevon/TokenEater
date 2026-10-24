import SwiftUI

/// Which provider layout Studio is editing.
///
/// Studio's surfaces are stored per provider mode, so editing the Codex
/// popover has always meant putting the app into Codex mode first. That was
/// invisible: nothing said the header pills were also the thing that chose
/// which layout you were about to change, and nothing said you had left the
/// app in another mode on your way out.
///
/// This control says it. It is deliberately not the header switcher with a
/// different size: that one is for reading, this one is for editing, and two
/// identical-looking controls doing different jobs is the confusion rather
/// than the fix. It wears a label, it sits inside Studio's own room, and the
/// header one is hidden while you are in here so there is only ever one
/// scope control on screen.
///
/// Picking a scope here switches the app's mode for real, and leaving Studio
/// keeps it: the layout you just edited is the one you see afterwards (#285).
/// The header switcher is back on screen outside Studio to change it.
///
/// Each running Claude account is a scope of its own, since its Claude mode
/// keeps its own layouts. When their names no longer fit the row, the pills
/// drop the names and keep the mark and the colour dot, the full name staying
/// in the tooltip.
struct StudioScopePicker: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    private var choices: [ModeChoice] { settingsStore.modeChoices }

    var body: some View {
        if choices.count > 1 {
            HStack(spacing: DS.Spacing.sm) {
                Text("studio.scope.label")
                    .font(DS.Typography.micro)
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Palette.textTertiary)

                ViewThatFits(in: .horizontal) {
                    pills(showsNames: true)
                    pills(showsNames: false)
                }

                Spacer(minLength: DS.Spacing.sm)

                Text("studio.scope.hint")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
        }
    }

    private func pills(showsNames: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(choices) { choice in
                pill(choice, showsName: showsNames)
            }
        }
        .fixedSize()
    }

    private func pill(_ choice: ModeChoice, showsName: Bool) -> some View {
        let isActive = settingsStore.isSelected(choice)
        let account = settingsStore.showsAccountMarkers ? choice.account.flatMap(settingsStore.claudeAccount) : nil
        return Button {
            guard !isActive else { return }
            settingsStore.selectScope(choice.mode, account: choice.account ?? .main)
        } label: {
            HStack(spacing: 4) {
                if let provider = choice.mode.provider {
                    ProviderGlyph(provider: provider, size: 14)
                }
                if let account {
                    AccountDot(colorHex: account.colorHex, size: 8)
                    if showsName {
                        Text(account.name)
                            .lineLimit(1)
                    }
                } else {
                    Text(choice.mode.localizedLabel)
                }
            }
            // Bigger than the header switcher on purpose. This one is a
            // deliberate, occasional choice rather than a control you flick
            // all day, and at 11pt in a quiet outline it did not read as
            // clickable at all.
            .font(.system(size: 12, weight: isActive ? .semibold : .medium))
            // Outlined when active, not filled: the header control is the
            // filled one, and the difference in register is the whole point.
            .foregroundStyle(isActive ? DS.Palette.accentHistory : DS.Palette.textSecondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? DS.Palette.accentHistory.opacity(0.14) : Color.white.opacity(0.05))
                    .overlay(
                        Capsule().stroke(
                            isActive ? DS.Palette.accentHistory.opacity(0.5) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // The full name for the narrow variant, nothing for the plain pills,
        // which carry their whole label already.
        .help(account?.name ?? "")
        .accessibilityLabel(account?.name ?? choice.mode.localizedLabel)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

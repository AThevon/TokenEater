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
/// Leaving Studio puts the app back in the mode it was in when you arrived,
/// so authoring a Codex layout never strands you in Codex mode.
struct StudioScopePicker: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    private var modes: [ProviderMode] { settingsStore.availableProviderModes }

    var body: some View {
        if modes.count > 1 {
            HStack(spacing: DS.Spacing.sm) {
                Text("studio.scope.label")
                    .font(DS.Typography.micro)
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Palette.textTertiary)

                HStack(spacing: 5) {
                    ForEach(modes) { mode in
                        pill(mode)
                    }
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

    private func pill(_ mode: ProviderMode) -> some View {
        let isActive = settingsStore.activeProviderMode == mode
        return Button {
            guard !isActive else { return }
            settingsStore.activeProviderMode = mode
        } label: {
            HStack(spacing: 4) {
                if let provider = mode.provider {
                    ProviderGlyph(provider: provider, size: 14)
                }
                Text(mode.localizedLabel)
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
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

import SwiftUI

/// Design-system dropdown that replaces the native `Picker(.menu)` style.
///
/// The default macOS Picker renders without a visible background, which makes
/// it disappear against TokenEater's dark glass cards. `DSMenu` wraps a `Menu`
/// in a styled capsule chip with a hover state, so users can actually see and
/// find the dropdown.
///
/// Generic over the selected value's type. Pass an array of options and a
/// closure to format each one into its human-readable label.
struct DSMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    var enabled: Bool = true

    @State private var isHovering = false

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { value in
                Button(label(value)) { selection = value }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label(selection))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.3))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(
                        enabled
                            ? (isHovering ? DS.Palette.accentSettings : .white.opacity(0.5))
                            : .white.opacity(0.25)
                    )
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // IMPORTANT: the capsule AND its padding sit on the `Menu`, never
        // inside the `label:` closure. Under `.menuStyle(.borderlessButton)`
        // AppKit re-renders the label through its own button cell, which paints
        // the text and silently drops a `.background()` and a `.padding()`
        // applied in there. That is why this control shipped as bare text and
        // a chevron, with no chip and no hover state, and why the fix for #167
        // had no visible effect (#251, diagnosed in an isolated harness by
        // @tarekrached). `AddElementMenuButton`, the sibling in this folder,
        // documents the same root cause and already takes this route.
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(enabled
                      ? (isHovering ? DS.Palette.glassFillHi : DS.Palette.glassFill)
                      : DS.Palette.glassFill.opacity(0.5))
                .overlay(
                    Capsule().stroke(
                        enabled
                            ? (isHovering ? DS.Palette.accentSettings.opacity(0.45) : DS.Palette.glassBorderHi)
                            : DS.Palette.glassBorderLo,
                        lineWidth: 0.8
                    )
                )
        )
        .disabled(!enabled)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

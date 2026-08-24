import SwiftUI

/// Compact violet "+ <title>" menu trigger used by the Studio composable
/// editors (popover composer, menu bar composer) to add a new element or
/// segment to a composition.
///
/// IMPORTANT: both the capsule `.background` AND the `.padding` are applied to
/// the `Menu` itself, never inside the `label:` closure. Verified empirically
/// (isolated SwiftUI harness, Xcode 26.6 / Swift 6.3.3): under
/// `.menuStyle(.borderlessButton)` AppKit re-renders the label through its own
/// button cell, which paints the text but silently drops both a `.background()`
/// and a `.padding()` applied inside that closure. A background there renders
/// as no capsule at all, and padding there leaves the text flush against the
/// capsule edge once the background is moved out on its own. Label internals
/// make no difference: per-child vs container-level `.foregroundStyle`,
/// `.contentShape`, and hover state were each tested and ruled out.
///
/// `EditorPickerLabel` in `MenuBarEditorView.swift` documents the same root
/// cause independently; its call sites use `.menuStyle(.button)` +
/// `.buttonStyle(.bordered)` specifically to avoid it. This view keeps the
/// custom capsule, so it takes the modifiers-on-`Menu` route instead.
///
/// Solid accent fill with inverted (near-black) text, so the label stays
/// legible on the editor's darkest surfaces - a translucent accent fill left
/// the text sitting on effectively raw background and was unreadable. The
/// hover lift and `.easeOut(0.12)` timing match `DSMenu`, the sibling
/// component in this folder.
struct AddElementMenuButton<MenuContent: View>: View {
    let title: String
    @ViewBuilder var menuContent: () -> MenuContent

    @State private var isHovering = false

    var body: some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
            }
            // Inverted: dark text on the light violet fill.
            .foregroundStyle(DS.Palette.bgElevated)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(DS.Palette.accentStudio)
                .overlay(Capsule().fill(.white.opacity(isHovering ? 0.18 : 0)))
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

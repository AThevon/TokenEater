import SwiftUI

/// Studio space -> the customization atelier. A strip of three live
/// mini-preview cards (`StudioSurfaceSwitcher`) switches between the
/// customizable surfaces; the matching editor fills the stage below. The
/// whole space sits on its own aurora ambient (`StudioBackground`) so it
/// reads as a distinct room while the window chrome stays untouched.
struct StudioRootView: View {
    @Binding var selection: StudioSection

    var body: some View {
        ZStack {
            StudioBackground()

            VStack(spacing: DS.Spacing.sm) {
                StudioSurfaceSwitcher(selection: $selection)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(DS.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.card)
                            .fill(DS.Palette.bgElevated.opacity(0.78))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.card)
                                    .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
                            )
                    )
            }
            .padding(DS.Spacing.sm)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous)
                .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .popover:
            // Owns its three-column layout (rail / list / pinned preview);
            // only the middle list scrolls, so it needs the full height.
            PopoverSectionView()
        case .menuBar:
            // Same three-column layout, driven by MenuBarEditorView.
            DisplaySectionView()
        case .themes:
            ScrollView(.vertical, showsIndicators: true) {
                ThemesSectionView()
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

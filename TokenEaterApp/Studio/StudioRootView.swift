import SwiftUI

/// Studio space -> the customization atelier. A strip of three live
/// mini-preview cards (`StudioSurfaceSwitcher`) switches between the
/// customizable surfaces; the matching editor fills the stage below. The
/// whole space sits on its own aurora ambient (`StudioBackground`) so it
/// reads as a distinct room while the window chrome stays untouched.
struct StudioRootView: View {
    @Binding var selection: StudioSection

    @EnvironmentObject private var settingsStore: SettingsStore
    /// The mode the app was reading in when Studio opened, restored on the way
    /// out so authoring a Codex layout never strands the app in Codex mode.
    @State private var modeOnEntry: ProviderMode?

    var body: some View {
        ZStack {
            StudioBackground()

            VStack(spacing: DS.Spacing.sm) {
                StudioSurfaceSwitcher(selection: $selection)

                // Under the surface cards, not above them: you pick the
                // surface you are working on first, then which provider's
                // version of it. Above, it read as a filter on the cards.
                //
                // Only the popover and the menu bar are stored per provider
                // mode. Themes are one set of colours and thresholds for the
                // whole app, so a scope control there would promise a
                // per-provider palette that does not exist.
                if selection != .themes {
                    StudioScopePicker()
                }

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
        .onAppear {
            if modeOnEntry == nil { modeOnEntry = settingsStore.activeProviderMode }
        }
        .onDisappear {
            if let modeOnEntry, modeOnEntry != settingsStore.activeProviderMode {
                settingsStore.activeProviderMode = modeOnEntry
            }
            modeOnEntry = nil
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
        case .dashboard:
            DashboardEditorView()
        case .popover:
            // Owns its three-column layout (rail / list / pinned preview);
            // only the middle list scrolls, so it needs the full height.
            PopoverSectionView()
        case .menuBar:
            // Same three-column layout, driven by MenuBarEditorView.
            DisplaySectionView()
        case .themes:
            // Owns its own three-column layout (GeometryReader) -> must fill
            // the pane directly, not sit inside a scroll view (a vertical
            // ScrollView would propose zero height and collapse it).
            ThemesSectionView()
        }
    }
}

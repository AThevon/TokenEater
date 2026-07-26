import SwiftUI

/// The menu bar dropdown. Renders the user's popover composition; the same
/// view doubles as the live preview inside the settings editor.
struct MenuBarPopoverView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ComposablePopoverView()
            .environment(\.glowIntensity, settingsStore.glowIntensity)
    }
}

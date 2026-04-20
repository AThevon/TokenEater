import SwiftUI

/// The menu bar dropdown. Hosts one of three variant layouts depending on
/// `settingsStore.popoverConfig.activeVariant`. A crossfade + subtle scale
/// animates the switch between variants so swapping in the settings panel
/// feels continuous.
struct MenuBarPopoverView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Group {
            switch settingsStore.popoverConfig.activeVariant {
            case .classic:
                ClassicLayoutView()
                    .transition(transition)
            case .compact:
                CompactLayoutView()
                    .transition(transition)
            case .focus:
                FocusLayoutView()
                    .transition(transition)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: settingsStore.popoverConfig.activeVariant)
    }

    private var transition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.97)),
            removal: .opacity
        )
    }
}

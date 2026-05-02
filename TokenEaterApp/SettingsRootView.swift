import SwiftUI

/// Settings space -> hosts the secondary sidebar (`SettingsSubSidebar`) and
/// dispatches to the correct configuration screen based on `selection`.
/// The six screens (general / display / themes / popover / agent watchers /
/// performance) remain in their existing files -> this view is just the
/// router.
struct SettingsRootView: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @Binding var selection: SettingsSection

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            SettingsSubSidebar(selection: $selection)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .fill(DS.Palette.bgElevated.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.card)
                                .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
                        )
                )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:
            scrolling { SettingsSectionView() }
        case .display:
            scrolling { DisplaySectionView(initialMetrics: settingsStore.pinnedMetrics) }
        case .themes:
            scrolling {
                ThemesSectionView(
                    initialWarning: themeStore.warningThreshold,
                    initialCritical: themeStore.criticalThreshold,
                    initialMargin: settingsStore.pacingMargin
                )
            }
        case .popover:
            // PopoverSectionView owns its own scroll (editor list) + needs
            // full height for the split layout.
            PopoverSectionView()
        case .agentWatchers:
            scrolling { AgentWatchersSectionView() }
        case .notifications:
            scrolling { NotificationsSectionView() }
        }
    }

    @ViewBuilder
    private func scrolling<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

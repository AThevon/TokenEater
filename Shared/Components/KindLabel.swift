import SwiftUI

/// An editor row's name, with its provider's mark in front of it.
///
/// The Codex kinds used to spell the provider into their own strings ("Codex
/// weekly") while the Claude ones did not ("Weekly"), so one provider read as
/// a variant of the other and the Claude rows never said whose they were at
/// all. Both sides carry the same name now and the mark says whose, which is
/// the same rule the popover cells and the dashboard cards follow.
///
/// The mark only appears with more than one provider on, because with one it
/// disambiguates nothing and costs width in a narrow editor list.
struct KindLabel: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    let provider: MetricProvider?
    let text: String
    var size: CGFloat = 12
    var weight: Font.Weight = .medium
    var color: Color = .white.opacity(0.9)

    var body: some View {
        HStack(spacing: 4) {
            if let provider, settingsStore.activeProviders.count > 1 {
                ProviderGlyph(provider: provider, size: size - 2)
            }
            Text(text)
        }
        .font(.system(size: size, weight: weight))
        .foregroundStyle(color)
        .lineLimit(1)
    }
}

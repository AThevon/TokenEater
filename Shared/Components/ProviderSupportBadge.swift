import SwiftUI

/// Which providers a feature serves, said in marks rather than in a sentence.
///
/// It goes on the header of any section whose providers disagree, so the
/// question "does this work with OpenAI" is answered where it is asked instead
/// of in a help page nobody opens. A feature both providers carry gets no
/// badge at all: a badge on everything is a badge on nothing.
struct ProviderSupportBadge: View {
    /// Either a declared capability, or a bare set for callers that have one
    /// (a dashboard block says who can draw it without being a capability).
    private let support: (MetricProvider) -> ProviderCapability.Support
    private let describes: String
    var size: CGFloat = 11

    init(capability: ProviderCapability, size: CGFloat = 11) {
        self.support = capability.support(for:)
        self.describes = capability.localizedName
        self.size = size
    }

    /// Prose does not scale: "Claude only" becomes "Claude, OpenAI and Gemini
    /// only" at four providers, in a row eleven points tall. Marks do: one
    /// glyph per provider, lit or dimmed, however many there are.
    init(providers: Set<MetricProvider>, describes: String = "", size: CGFloat = 11) {
        self.support = { providers.contains($0) ? .full : .none }
        self.describes = describes
        self.size = size
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(MetricProvider.allCases) { provider in
                ProviderGlyph(provider: provider, size: size)
                    .foregroundStyle(tint(for: provider))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.white.opacity(0.05))
                .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))
        )
        .help(tooltip)
        .accessibilityElement()
        .accessibilityLabel(tooltip)
    }

    private func tint(for provider: MetricProvider) -> Color {
        switch support(provider) {
        case .full:    return DS.Palette.textSecondary
        case .partial: return DS.Palette.semanticWarning.opacity(0.75)
        // Dimmed rather than absent: an unsupported provider that vanished
        // would read as "this feature only knows about one provider", which is
        // the same ambiguity the badge exists to remove.
        case .none:    return DS.Palette.textPrimary.opacity(0.16)
        }
    }

    /// Named first when the caller gave a name: the badge is eleven points of
    /// glyphs, and a tooltip that opens with "Claude: full" leaves the reader
    /// to work out full what.
    private var tooltip: String {
        let lines = MetricProvider.allCases.map { provider in
            let state: String
            switch support(provider) {
            case .full:              state = String(localized: "coverage.legend.full")
            case .partial(let why):  state = why
            case .none:              state = String(localized: "coverage.legend.none")
            }
            return "\(provider.displayName): \(state)"
        }.joined(separator: "\n")
        return describes.isEmpty ? lines : describes + "\n" + lines
    }
}

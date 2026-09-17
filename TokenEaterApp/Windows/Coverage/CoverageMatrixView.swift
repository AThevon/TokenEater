import SwiftUI

/// The whole capability declaration, rendered.
///
/// One component, two hosts: the Coverage section in Settings, and the first
/// pane of the what's-new window. The rows come from `ProviderCapability`, so
/// this is never a list someone has to remember to update.
struct CoverageMatrixView: View {
    /// The what's-new pane animates the rows in; Settings shows them at rest.
    var animated: Bool = false
    /// The pane's own title already says what this is, so it repeats itself
    /// there. Settings needs the heading, having no title above it.
    var showsHeading: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    /// Narrow enough that a row's label and its marks read as one line.
    /// At 74 with a flexible label the two ends of a row were 500 points
    /// apart and the table stopped looking like rows at all.
    private let columnWidth: CGFloat = 58

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Array(ProviderCapability.allCases.enumerated()), id: \.element.id) { index, capability in
                row(capability, index: index)
            }
            legend
        }
        .onAppear { revealed = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            if showsHeading {
                Text("coverage.title")
                    .font(DS.Typography.micro)
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Spacer(minLength: DS.Spacing.sm)

            ForEach(MetricProvider.allCases) { provider in
                VStack(spacing: 4) {
                    ProviderGlyph(provider: provider, size: 15)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(provider.displayName.uppercased())
                        .font(.system(size: 8, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .frame(width: columnWidth)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Rows

    private func row(_ capability: ProviderCapability, index: Int) -> some View {
        HStack(spacing: 0) {
            Text(capability.localizedName)
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(MetricProvider.allCases) { provider in
                mark(capability.support(for: provider))
                    .frame(width: columnWidth)
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            // Rules between rows, never above the first: a line under the
            // column heads and another straight after it read as a boxed
            // table header this design does not have.
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .opacity(index == 0 ? 0 : 1)
        }
        .opacity(animated && !revealed ? 0 : 1)
        .offset(y: animated && !revealed && !reduceMotion ? 8 : 0)
        // The stagger is the whole point of the animated variant: a row only
        // one provider carries holds a visible beat before its second mark
        // fails to land, so a gap is something you watch happen rather than
        // something you have to go looking for.
        .animation(
            animated && !reduceMotion ? DS.Motion.easeOut.delay(Double(index) * 0.045) : nil,
            value: revealed
        )
    }

    @ViewBuilder
    private func mark(_ support: ProviderCapability.Support) -> some View {
        switch support {
        case .full:
            Circle()
                .fill(DS.Palette.brandPrimary)
                .frame(width: 8, height: 8)
        case .partial(let why):
            Circle()
                .fill(DS.Palette.semanticWarning)
                .frame(width: 8, height: 8)
                .help(why)
        case .none:
            Circle()
                .strokeBorder(DS.Palette.textPrimary.opacity(0.18), lineWidth: 1)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(DS.Palette.brandPrimary, "coverage.legend.full", filled: true)
            legendItem(DS.Palette.semanticWarning, "coverage.legend.partial", filled: true)
            legendItem(DS.Palette.textPrimary.opacity(0.18), "coverage.legend.none", filled: false)
        }
        .padding(.top, 14)
    }

    private func legendItem(_ color: Color, _ key: LocalizedStringKey, filled: Bool) -> some View {
        HStack(spacing: 5) {
            Group {
                if filled { Circle().fill(color) } else { Circle().strokeBorder(color, lineWidth: 1) }
            }
            .frame(width: 7, height: 7)
            Text(key)
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.textTertiary)
        }
    }
}

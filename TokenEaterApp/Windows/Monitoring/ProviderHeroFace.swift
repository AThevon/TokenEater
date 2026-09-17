import SwiftUI

/// The face both glance cards wear.
///
/// It used to be Claude's alone, written inline in `MonitoringView`, and the
/// Codex card was a separate approximation of it. Side by side the two drifted
/// visibly: 64pt bold with a separate oversized "%" against 46pt semibold with
/// the sign inline, an uppercase tracked "RESETS IN 3h34 · 15:20" against a
/// lowercase "1h59 reset", a 140pt ring carrying the pacing animal against a
/// bare 104pt one.
///
/// Extracting it rather than copying Claude's markup into the Codex card is
/// the point: two copies drift again on the next change, and the whole claim
/// of the provider work is that the two read as peers.
struct ProviderHeroFace: View {
    let provider: MetricProvider
    /// Already localized, not yet uppercased.
    let windowLabel: String
    let pct: Int
    let gaugeColor: Color
    let gaugeGradient: LinearGradient
    /// Nil draws the neutral glyph, which is what a provider with no pacing
    /// data for this window gets.
    let zone: PacingZone?
    /// Relative countdown, already formatted ("3h34").
    let resetText: String
    let resetDate: Date?

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.glowIntensity) private var glowIntensity

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                // The provider mark stands where the status dot used to, so it
                // carries identity and risk colour in one element rather than
                // adding a second mark to the row.
                HStack(spacing: DS.Spacing.xs) {
                    ProviderGlyph(provider: provider, size: 11)
                        .foregroundStyle(gaugeColor)
                        .dsGlow(gaugeColor, radius: 4, opacity: 0.6)
                    Text(provider.displayName.uppercased() + " · " + windowLabel.uppercased())
                        .font(DS.Typography.micro)
                        .tracking(1.5)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(pct)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(gaugeColor)
                        .dsGlow(gaugeColor, radius: 10, opacity: 0.45)
                        .contentTransition(.numericText(value: Double(pct)))
                        .animation(DS.Motion.springLiquid, value: pct)
                    Text("%")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(gaugeColor.opacity(0.55))
                        .baselineOffset(5)
                }

                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                    Text(String(localized: "dashboard.hero.resetsIn").uppercased())
                        .font(DS.Typography.micro)
                        .tracking(1.2)
                        .foregroundStyle(DS.Palette.textTertiary)
                    Text(resetText.isEmpty ? "-" : resetText)
                        .font(DS.Typography.metricInline)
                        .foregroundStyle(DS.Palette.textPrimary)
                    if let resetDate {
                        Text("·")
                            .font(DS.Typography.metricInline)
                            .foregroundStyle(DS.Palette.textTertiary.opacity(0.5))
                        Text(resetDate.formatted(.dateTime.hour().minute()))
                            .font(DS.Typography.metricInline)
                            .foregroundStyle(DS.Palette.textPrimary)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                if glowIntensity == .glow {
                    RadialGradient(
                        colors: [gaugeColor.opacity(0.20), gaugeColor.opacity(0.04), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 90
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 14)
                    // Flattened to one bitmap: a 14pt blur over a 200pt
                    // gradient is the single most expensive thing on this
                    // card, and its own frame never changes, so paying for it
                    // once per appearance instead of once per frame of the
                    // card's resize costs nothing visually.
                    .drawingGroup()
                    .allowsHitTesting(false)
                }

                RingGauge(
                    percentage: pct,
                    gradient: gaugeGradient,
                    size: 140,
                    glowColor: gaugeColor,
                    glowRadius: 8
                )

                Image(systemName: Self.zoneGlyph(for: zone))
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(zone.map { themeStore.current.pacingColor(for: $0) } ?? gaugeColor)
                    .dsGlow(zone.map { themeStore.current.pacingColor(for: $0) } ?? gaugeColor,
                            radius: 10, opacity: 0.55)
                    .animation(DS.Motion.springLiquid, value: zone)
            }
            .frame(width: 160, height: 160)
        }
    }

    static func zoneGlyph(for zone: PacingZone?) -> String {
        switch zone {
        case .chill:   "leaf.fill"
        case .onTrack: "bolt.fill"
        case .warning: "hare.fill"
        case .hot:     "flame.fill"
        case nil:      "sparkles"
        }
    }
}

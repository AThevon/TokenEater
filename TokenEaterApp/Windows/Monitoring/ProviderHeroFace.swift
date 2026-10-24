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
    /// Overrides the provider's name in the label, for an added Claude
    /// account ("Work"), which draws with Claude's provider.
    var name: String? = nil
    /// Set while the numbers are the last known ones of a login that no
    /// longer answers: the reset line then says how old they are instead of
    /// counting down to a reset that may already have passed.
    var lastNumbersDate: Date? = nil
    /// False for a login that failed with nothing to show: the number reads
    /// "--" and the line under it says so, never a 0% that would pass for a
    /// fresh reading.
    var hasNumbers: Bool = true
    @Environment(\.glowIntensity) private var glowIntensity
    /// A header above the column names it already: the label keeps the
    /// window alone, and the provider's mark beside it.
    @Environment(\.dashboardColumnHeaded) private var columnHeaded

    /// The ring's sizes, largest first. The card picks the largest that
    /// leaves the label, the number and the reset line their full width, so
    /// a narrow column shrinks the ring rather than the number.
    private enum RingSize: CaseIterable {
        case large, medium, small, none

        var gauge: CGFloat {
            switch self {
            case .large: 140
            case .medium: 104
            case .small: 76
            case .none: 0
            }
        }
        var box: CGFloat {
            switch self {
            case .large: 160
            case .medium: 116
            case .small: 84
            case .none: 0
            }
        }
        var glyph: CGFloat {
            switch self {
            case .large: 40
            case .medium: 30
            case .small: 22
            case .none: 0
            }
        }
        var spacing: CGFloat {
            switch self {
            case .large: DS.Spacing.lg
            case .medium: DS.Spacing.md
            case .small, .none: DS.Spacing.sm
            }
        }
    }

    var body: some View {
        // The ring is the card's signature, so the "resets in" words go
        // before it shrinks; the number never gives way. The last face is
        // taken whatever the width, and its reset line sheds what it must.
        ViewThatFits(in: .horizontal) {
            face(ring: .large, resetWords: true)
            face(ring: .large, resetWords: false)
            face(ring: .medium, resetWords: false)
            face(ring: .small, resetWords: false)
            face(ring: .none, resetWords: true)
        }
    }

    private var title: String {
        let window = windowLabel.uppercased()
        guard !columnHeaded else { return window }
        return (name ?? provider.displayName).uppercased() + " · " + window
    }

    /// - Parameter resetWords: whether the reset line starts with its
    ///   "resets in" words. Either way it sheds what does not fit.
    private func face(ring: RingSize, resetWords: Bool) -> some View {
        HStack(alignment: .center, spacing: ring.spacing) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                // The provider mark stands where the status dot used to, so it
                // carries identity and risk colour in one element rather than
                // adding a second mark to the row.
                HStack(spacing: DS.Spacing.xs) {
                    ProviderGlyph(provider: provider, size: 11)
                        .foregroundStyle(gaugeColor)
                        .dsGlow(gaugeColor, radius: 4, opacity: 0.6)
                    Text(title)
                        .font(DS.Typography.micro)
                        .tracking(1.5)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }

                // Never truncated: this number is what the card is for. The
                // ring gives way before it does. The face measures itself
                // as if it read 100%, so two cards side by side settle on
                // the same ring whatever their numbers, and a card does not
                // change shape when its number gains a digit.
                ZStack(alignment: .leading) {
                    number("100")
                        .hidden()
                        .accessibilityHidden(true)
                    if hasNumbers {
                        number("\(pct)")
                    } else {
                        number("--", percent: false)
                    }
                }
                .fixedSize()
                .layoutPriority(1)

                if !hasNumbers {
                    noNumbersLine
                } else if let lastNumbersDate {
                    lastNumbersLine(lastNumbersDate)
                } else {
                    ViewThatFits(in: .horizontal) {
                        if resetWords {
                            resetLine(words: true, clock: true)
                        }
                        resetLine(words: false, clock: true)
                        resetLine(words: false, clock: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if ring != .none {
                gauge(ring)
            }
        }
    }

    private func number(_ value: String, percent: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(gaugeColor)
                .dsGlow(gaugeColor, radius: 10, opacity: 0.45)
                .contentTransition(.numericText(value: Double(pct)))
                .animation(DS.Motion.springLiquid, value: pct)
            if percent {
                Text("%")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(gaugeColor.opacity(0.55))
                    .baselineOffset(5)
            }
        }
    }

    /// "NO NUMBERS YET", in place of a countdown there is nothing to base on.
    private var noNumbersLine: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.textTertiary)
            Text(String(localized: "dashboard.hero.noNumbers").uppercased())
                .font(DS.Typography.micro)
                .tracking(1.2)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .lineLimit(1)
    }

    /// The reset line measures itself as if it read a full countdown and a
    /// clock time, like the number reads 100%: two cards side by side then
    /// keep or drop their "resets in" words together, whatever their own
    /// values (a "-" for a login with no numbers is much shorter than
    /// "3h43 · 15:20").
    private func resetLine(words: Bool, clock: Bool) -> some View {
        ZStack(alignment: .leading) {
            resetLine(words: words, countdown: Self.countdownTemplate(for: resetText),
                      clockTime: clock ? Self.clockTemplate : nil)
                .hidden()
                .accessibilityHidden(true)
            resetLine(words: words, countdown: resetText.isEmpty ? "-" : resetText,
                      clockTime: clock ? resetDate?.formatted(.dateTime.hour().minute()) : nil)
        }
    }

    /// "LAST NUMBERS 2 days ago", re-read every minute so the age keeps up
    /// while the window stays open. The words go first when room runs out.
    private func lastNumbersLine(_ date: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let age = date.formatted(.relative(presentation: .named))
            ViewThatFits(in: .horizontal) {
                lastNumbersLine(age: age, words: true)
                lastNumbersLine(age: age, words: false)
            }
        }
    }

    private func lastNumbersLine(age: String, words: Bool) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.textTertiary)
            if words {
                Text(String(localized: "dashboard.hero.lastNumbers").uppercased())
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Text(age)
                .font(DS.Typography.metricInline)
                .foregroundStyle(DS.Palette.textSecondary)
        }
        .lineLimit(1)
    }

    /// A countdown as wide as this window's can get: days and hours for a
    /// weekly window, hours and minutes otherwise.
    private static func countdownTemplate(for resetText: String) -> String {
        resetText.contains("d") ? "0d 00h" : "00h00"
    }

    /// A clock time as wide as the locale writes one.
    private static let clockTemplate: String = {
        let late = DateComponents(calendar: .current, year: 2026, month: 1, day: 1, hour: 22, minute: 58)
        return (late.date ?? .now).formatted(.dateTime.hour().minute())
    }()

    /// The countdown is the line's largest text (#295), so everything else
    /// sits on its baseline rather than on its centre.
    private func resetLine(words: Bool, countdown: String, clockTime: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.textTertiary)
            if words {
                Text(String(localized: "dashboard.hero.resetsIn").uppercased())
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Text(countdown)
                .font(DS.Typography.countdown(17, monospaced: true))
                .foregroundStyle(DS.Palette.textPrimary)
            if let clockTime {
                Text("·")
                    .font(DS.Typography.metricInline)
                    .foregroundStyle(DS.Palette.textTertiary.opacity(0.5))
                Text(clockTime)
                    .font(DS.Typography.metricInline)
                    .foregroundStyle(DS.Palette.textPrimary)
            }
        }
        .lineLimit(1)
    }

    private func gauge(_ ring: RingSize) -> some View {
        ZStack {
            if glowIntensity == .glow {
                RadialGradient(
                    colors: [gaugeColor.opacity(0.20), gaugeColor.opacity(0.04), .clear],
                    center: .center,
                    startRadius: 10,
                    endRadius: ring.box * 0.56
                )
                .frame(width: ring.box * 1.25, height: ring.box * 1.25)
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
                size: ring.gauge,
                glowColor: gaugeColor,
                glowRadius: 8
            )

            Image(systemName: Self.zoneGlyph(for: zone))
                .font(.system(size: ring.glyph, weight: .semibold))
                .foregroundStyle(zone.map { themeStore.current.pacingColor(for: $0) } ?? gaugeColor)
                .dsGlow(zone.map { themeStore.current.pacingColor(for: $0) } ?? gaugeColor,
                        radius: 10, opacity: 0.55)
                .animation(DS.Motion.springLiquid, value: zone)
        }
        .frame(width: ring.box, height: ring.box)
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

extension View {
    /// Greys a block or a cell whose numbers are the last known ones of a
    /// login that no longer answers, so they never pass for live readings.
    /// Risk colours go (they describe a now the numbers do not), and the
    /// content stays legible.
    func lastNumbersDimmed(_ dimmed: Bool) -> some View {
        saturation(dimmed ? 0 : 1)
            .opacity(dimmed ? 0.55 : 1)
    }
}

import SwiftUI

// MARK: - Tile descriptor + MetricTile

struct TileDescriptor {
    let id: String
    let label: String
    let icon: String
    let pct: Int
    let resetText: String?
    let resetDate: Date?
    let windowDuration: TimeInterval
}

struct MetricTile: View {
    let id: String
    let label: String
    let icon: String
    let pct: Int
    let resetText: String?
    let resetDate: Date?
    let windowDuration: TimeInterval
    let smartEnabled: Bool
    let pacingMargin: Double
    let smartProfile: SmartColorProfile
    let themeStore: ThemeStore
    /// 7d insights snapshot when the tile family has data. Nil for
    /// design / cowork tiles where the JSONL feed has nothing relevant.
    let insights: TileInsightsSnapshot?
    /// True once the insights store has done its first load. Lets the
    /// back face show a "loading..." placeholder vs a "no data" one.
    let insightsLoaded: Bool

    @State private var isHovered: Bool = false
    @State private var showBack: Bool = false
    @State private var blurProgress: CGFloat = 0
    @State private var isFlipping: Bool = false

    var body: some View {
        let color = GaugeColorResolver.color(
            mode: GaugeColorResolver.mode(smartColorEnabled: smartEnabled, windowDuration: windowDuration),
            utilization: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            theme: themeStore.current,
            thresholds: themeStore.thresholds,
            pacingMargin: pacingMargin,
            profile: smartProfile
        )
        let clamped = CGFloat(min(max(pct, 0), 100)) / 100

        return Button {
            triggerFlip()
        } label: {
            ZStack {
                if showBack {
                    backContent(color: color)
                } else {
                    frontContent(color: color, clamped: clamped)
                }
            }
            // Snap swap (no implicit animation) so the new face is in
            // place at the blur peak rather than crossfading during it.
            .animation(nil, value: showBack)
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 124)
            .blur(radius: blurProgress * 14.0)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .fill(DS.Palette.bgPanel.opacity(0.92))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .fill(LinearGradient(colors: [color.opacity(isHovered ? 0.10 : 0.05), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .stroke(color.opacity(isHovered ? 0.40 : 0.18), lineWidth: 1)
            )
            .dsShadow(isHovered ? DS.Shadow.lift : DS.Shadow.subtle)
        }
        .buttonStyle(CardPressStyle(isHovered: isHovered, accent: color, cornerRadius: DS.Radius.card))
        .onHover { hovering in
            withAnimation(DS.Motion.springSnap) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private func frontContent(color: Color, clamped: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color.opacity(0.8))
                    .frame(width: 14)
                Text(label.uppercased())
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(pct)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(pct)))
                    .animation(DS.Motion.springLiquid, value: pct)
                Text("%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(color.opacity(0.55))
                    .baselineOffset(3)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.Palette.glassFillHi)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * clamped, height: 3)
                        .dsGlow(color, radius: 3, opacity: 0.5)
                }
            }
            .frame(height: 3)
            .animation(DS.Motion.springLiquid, value: pct)

            Group {
                if let resetText, !resetText.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(String(localized: "dashboard.hero.resetsIn").uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(resetText)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(DS.Palette.textSecondary)
                        if let resetDate {
                            Text("·")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DS.Palette.textTertiary.opacity(0.5))
                            Text(absoluteResetText(date: resetDate))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(DS.Palette.textSecondary)
                        }
                    }
                } else {
                    Text(" ")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.clear)
                }
            }
            .lineLimit(1)
        }
    }

    /// "16:32" for sub-day windows (5h), "Tue 16:32" for multi-day
    /// windows (7d weeklies). Stays compact + monospaced so it sits
    /// discretely next to the countdown without competing for space.
    private func absoluteResetText(date: Date) -> String {
        if windowDuration <= 24 * 3600 {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// Back face - "details" view. When `insights` is available (weekly,
    /// sonnet, opus tiles) we show a rich 7d breakdown; otherwise we
    /// fall back to a minimal placeholder. Card dimensions match the
    /// front via the parent's fixed height.
    @ViewBuilder
    private func backContent(color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header line: same icon + label structure as the front so
            // the card identity stays anchored across the swap.
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color.opacity(0.8))
                    .frame(width: 14)
                Text("\(label.uppercased()) · 7D")
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let delta = insights?.deltaPercent {
                    Text(String(format: "%+.0f%%", delta))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(delta >= 0 ? DS.Palette.semanticWarning : DS.Palette.brandPrimary)
                        .monospacedDigit()
                }
            }

            if let snapshot = insights {
                richBackBody(snapshot: snapshot, color: color)
            } else if !insightsLoaded {
                Spacer(minLength: 0)
                Text("Loading...")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                fallbackBackBody(color: color)
            }
        }
    }

    @ViewBuilder
    private func richBackBody(snapshot: TileInsightsSnapshot, color: Color) -> some View {
        // Mini sparkline of the 7 daily totals.
        sparklineBars(snapshot.sparkline, color: color)

        Spacer(minLength: 0)

        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("TOTAL")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(DS.Palette.textTertiary)
                Text(TokenFormatter.compact(snapshot.total))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            if let heaviest = snapshot.heaviestDay {
                VStack(alignment: .leading, spacing: 1) {
                    Text("PEAK")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(DS.Palette.textTertiary)
                    HStack(spacing: 4) {
                        Text(heaviest.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Palette.textPrimary)
                        Text(TokenFormatter.compact(heaviest.tokens))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Fallback when no JSONL family data exists for this tile (design /
    /// cowork). Keeps the card useful by surfacing the full reset date
    /// instead of leaving the back empty.
    @ViewBuilder
    private func fallbackBackBody(color: Color) -> some View {
        Spacer(minLength: 0)
        if let resetDate {
            VStack(alignment: .leading, spacing: 2) {
                Text("RESETS")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(DS.Palette.textTertiary)
                Text(resetDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        Text(windowText)
            .font(.system(size: 9))
            .foregroundStyle(DS.Palette.textTertiary)
    }

    /// 7-bar mini chart showing daily totals. Bars share their height
    /// scale with the maximum value in the series so the relative
    /// distribution reads correctly even when totals are tiny.
    private func sparklineBars(_ values: [Int], color: Color) -> some View {
        let maxValue = max(values.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                let h = CGFloat(value) / CGFloat(maxValue)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(LinearGradient(
                        colors: [color, color.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, 32 * h))
                    .opacity(value > 0 ? 1 : 0.18)
            }
        }
        .frame(height: 32)
        .padding(.top, 2)
    }

    private var windowText: String {
        let hours = Int(windowDuration / 3600)
        if hours <= 24 { return "\(hours)h rolling" }
        let days = Int(windowDuration / 86_400)
        return "\(days)d rolling"
    }

    private func triggerFlip() {
        guard !isFlipping else { return }
        isFlipping = true
        withAnimation(.easeIn(duration: 0.16)) { blurProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            // Snap swap (no animation) so the back content appears
            // INSTANTLY at the blur peak. Any animation here would
            // visibly fade the new content while the blur is still
            // dropping, producing the "weird blink" we're avoiding.
            showBack.toggle()
            withAnimation(.easeOut(duration: 0.24)) { blurProgress = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                isFlipping = false
            }
        }
    }
}

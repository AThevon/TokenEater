import SwiftUI

// MARK: - Element cell dispatch
//
// One small view per element style, all sharing the same card language
// (radius 12, white 3% fill, hairline border) and the same color pipeline
// (`PopoverColors` -> `GaugeColorResolver`). The dispatcher below is the only
// place that knows which style maps to which cell.

struct PopoverElementCellView: View {
    @EnvironmentObject private var usageStore: UsageStore

    let element: PopoverElement

    var body: some View {
        switch element.style {
        case .gaugeRing:
            if let snapshot = PopoverMetricResolver.usageSnapshot(for: element.kind, usage: usageStore) {
                GaugeRingCell(snapshot: snapshot, width: element.effectiveWidth, showReset: element.options.showReset)
            }
        case .chip:
            if let snapshot = PopoverMetricResolver.usageSnapshot(for: element.kind, usage: usageStore) {
                ChipCell(snapshot: snapshot, width: element.effectiveWidth, showReset: element.options.showReset)
            }
        case .arc:
            if let snapshot = PopoverMetricResolver.usageSnapshot(for: element.kind, usage: usageStore) {
                ArcCell(snapshot: snapshot, content: element.options.content)
            }
        case .bigText:
            if let snapshot = PopoverMetricResolver.usageSnapshot(for: element.kind, usage: usageStore) {
                BigTextCell(snapshot: snapshot, width: element.effectiveWidth, content: element.options.content)
            }
        case .paceBar:
            if let pacing = PopoverMetricResolver.pacing(for: element.kind, usage: usageStore) {
                PopoverPacingRow(
                    label: element.kind == .weeklyPacing
                        ? String(localized: "pacing.weekly.label")
                        : String(localized: "pacing.session.label"),
                    pacing: pacing,
                    showWorkweekBadge: element.kind == .weeklyPacing
                )
            }
        case .paceTile:
            if let pacing = PopoverMetricResolver.pacing(for: element.kind, usage: usageStore) {
                PaceTileCell(label: paceShortLabel, pacing: pacing)
            }
        case .paceText:
            if let pacing = PopoverMetricResolver.pacing(for: element.kind, usage: usageStore) {
                PaceTextCell(label: paceShortLabel, pacing: pacing)
            }
        case .utilityRow:
            switch element.kind {
            case .watchers: PopoverWatchersToggle()
            case .timestamp: PopoverTimestamp()
            default: EmptyView()
            }
        case .actionButton:
            switch element.kind {
            case .openButton: PopoverOpenButton()
            case .quitButton: PopoverQuitButtonCell(width: element.effectiveWidth)
            default: EmptyView()
            }
        }
    }

    private var paceShortLabel: String {
        element.kind == .weeklyPacing
            ? String(localized: "pacing.weekly.label.short")
            : String(localized: "pacing.session.label.short")
    }
}

// MARK: - Gauge ring (full = hero 100px, half = 70px, third = satellite 46px)

private struct GaugeRingCell: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    let snapshot: PopoverMetricResolver.UsageSnapshot
    let width: PopoverElementWidth
    let showReset: Bool

    var body: some View {
        let color = PopoverColors.gauge(
            pct: snapshot.pct, resetDate: snapshot.resetDate,
            windowDuration: snapshot.windowDuration,
            theme: themeStore, settings: settingsStore
        )
        let gradient = PopoverColors.gaugeGradient(
            pct: snapshot.pct, resetDate: snapshot.resetDate,
            windowDuration: snapshot.windowDuration,
            theme: themeStore, settings: settingsStore
        )

        VStack(spacing: width == .third ? 4 : 8) {
            ZStack {
                RingGauge(
                    percentage: snapshot.pct,
                    gradient: gradient,
                    size: ringSize,
                    glowColor: color,
                    glowRadius: glowRadius
                )
                if width == .third {
                    GlowText(
                        "\(snapshot.pct)%",
                        font: .system(size: 11, weight: .black, design: .rounded),
                        color: color,
                        glowRadius: 2
                    )
                } else {
                    VStack(spacing: 2) {
                        GlowText(
                            "\(snapshot.pct)%",
                            font: .system(size: valueFontSize, weight: .black, design: .rounded),
                            color: color,
                            glowRadius: width == .full ? 4 : 3
                        )
                        Text(snapshot.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            if width == .third {
                Text(snapshot.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            if showReset && !snapshot.resetText.isEmpty {
                Text(String(format: String(localized: "metric.reset"), snapshot.resetText))
                    .font(.system(size: width == .third ? 8 : 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, width == .full ? 8 : 2)
    }

    private var ringSize: CGFloat {
        switch width {
        case .full: return 100
        case .half: return 70
        case .third: return 46
        }
    }

    private var valueFontSize: CGFloat {
        width == .full ? 24 : 16
    }

    private var glowRadius: CGFloat {
        switch width {
        case .full: return 6
        case .half: return 4
        case .third: return 3
        }
    }
}

// MARK: - Chip (card + mini trimmed ring; full / half only)

private struct ChipCell: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    let snapshot: PopoverMetricResolver.UsageSnapshot
    let width: PopoverElementWidth
    let showReset: Bool

    var body: some View {
        let color = PopoverColors.gauge(
            pct: snapshot.pct, resetDate: snapshot.resetDate,
            windowDuration: snapshot.windowDuration,
            theme: themeStore, settings: settingsStore
        )

        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 4)
                    .frame(width: 38, height: 38)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(snapshot.pct, 0), 100)) / 100.0)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(-90))
                    .dsGlow(color, radius: 3, opacity: 0.4)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(0.5)
                    .lineLimit(1)
                Text("\(snapshot.pct)%")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(color)
                if showReset && !snapshot.resetText.isEmpty {
                    Text(String(format: String(localized: "metric.reset"), snapshot.resetText))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .popoverCard()
    }
}

// MARK: - Arc (open half-arc hero, ex-Focus)

private struct ArcCell: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    let snapshot: PopoverMetricResolver.UsageSnapshot
    let content: PopoverMetricContent

    var body: some View {
        ZStack {
            arc
            VStack(spacing: 4) {
                Text(displayValue)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(color)
                    .dsGlow(color, radius: 10, opacity: 0.35)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1)
            }
        }
        .frame(height: 150)
    }

    private var displayValue: String {
        switch content {
        case .percent: return "\(snapshot.pct)%"
        case .resetCountdown: return snapshot.resetText.isEmpty ? "-" : snapshot.resetText
        }
    }

    private var label: String {
        switch content {
        case .percent: return snapshot.label
        case .resetCountdown: return String(format: String(localized: "popover.cell.resetLabel"), snapshot.label)
        }
    }

    private var color: Color {
        switch content {
        case .resetCountdown:
            return PopoverCellPalette.countdown
        case .percent:
            return PopoverColors.gauge(
                pct: snapshot.pct, resetDate: snapshot.resetDate,
                windowDuration: snapshot.windowDuration,
                theme: themeStore, settings: settingsStore
            )
        }
    }

    private var progress: Double {
        switch content {
        case .percent:
            return Double(min(max(snapshot.pct, 0), 100)) / 100.0
        case .resetCountdown:
            guard let date = snapshot.resetDate, snapshot.windowDuration > 0 else { return 0 }
            let remaining = max(date.timeIntervalSinceNow, 0)
            let elapsed = max(snapshot.windowDuration - remaining, 0)
            return min(elapsed / snapshot.windowDuration, 1)
        }
    }

    /// Open arc drawn from bottom-left to bottom-right of the cell.
    private var arc: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let strokeW: CGFloat = 8
            let inset: CGFloat = strokeW / 2 + 4
            let rect = CGRect(x: inset, y: inset, width: w - inset * 2, height: (h - inset) * 2)
            let path = Path { p in
                p.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2,
                    startAngle: .degrees(180),
                    endAngle: .degrees(360),
                    clockwise: false
                )
            }
            ZStack {
                path
                    .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                path
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                    .dsGlow(color, radius: 8, opacity: 0.5)
            }
        }
    }
}

// MARK: - Big text (value + label card, ex-Focus satellite)

private struct BigTextCell: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    let snapshot: PopoverMetricResolver.UsageSnapshot
    let width: PopoverElementWidth
    let content: PopoverMetricContent

    var body: some View {
        VStack(spacing: 4) {
            Text(displayValue)
                .font(.system(size: valueFontSize, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .popoverCard()
    }

    private var valueFontSize: CGFloat {
        switch width {
        case .full: return 24
        case .half: return 20
        case .third: return 16
        }
    }

    private var displayValue: String {
        switch content {
        case .percent: return "\(snapshot.pct)%"
        case .resetCountdown: return snapshot.resetText.isEmpty ? "-" : snapshot.resetText
        }
    }

    private var label: String {
        switch content {
        case .percent: return snapshot.label
        case .resetCountdown: return String(format: String(localized: "popover.cell.resetLabel"), snapshot.label)
        }
    }

    private var color: Color {
        switch content {
        case .resetCountdown:
            return PopoverCellPalette.countdown
        case .percent:
            return PopoverColors.gauge(
                pct: snapshot.pct, resetDate: snapshot.resetDate,
                windowDuration: snapshot.windowDuration,
                theme: themeStore, settings: settingsStore
            )
        }
    }
}

// MARK: - Pace tile (carded bar + delta, ex-Compact)

private struct PaceTileCell: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let label: String
    let pacing: PacingResult

    var body: some View {
        let color = PopoverColors.zone(pacing.zone, theme: themeStore)
        let sign = pacing.delta >= 0 ? "+" : ""
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("\(sign)\(Int(pacing.delta))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            PacingBar(
                actual: pacing.actualUsage,
                expected: pacing.expectedUsage,
                zone: pacing.zone,
                gradient: PopoverColors.zoneGradient(pacing.zone, theme: themeStore),
                compact: true
            )
        }
        .padding(10)
        .popoverCard()
    }
}

// MARK: - Pace text (delta only, ex-Focus mini row)

private struct PaceTextCell: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let label: String
    let pacing: PacingResult

    var body: some View {
        let color = PopoverColors.zone(pacing.zone, theme: themeStore)
        let sign = pacing.delta >= 0 ? "+" : ""
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text("\(sign)\(Int(pacing.delta))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .popoverCard()
    }
}

// MARK: - Quit button (plain text full width for legacy continuity, capsule
// when sharing a row so it visually matches its neighbor)

private struct PopoverQuitButtonCell: View {
    let width: PopoverElementWidth

    var body: some View {
        if width == .full {
            PopoverQuitButton()
        } else {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 8))
                    Text(String(localized: "menubar.quit"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.white.opacity(0.05))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Shared card language

private struct PopoverCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

private extension View {
    /// The unified cell card: radius 12, white 3% fill, hairline border.
    func popoverCard() -> some View {
        modifier(PopoverCardModifier())
    }
}

enum PopoverCellPalette {
    /// Warm yellow used for reset countdown values (same as the old Focus hero).
    static let countdown = Color(red: 0.99, green: 0.90, blue: 0.54)
}

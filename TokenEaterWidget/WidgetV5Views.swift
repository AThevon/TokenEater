import SwiftUI
import WidgetKit

// =====================================================================
// MARK: - Design tokens for widgets (v5.1 reskin)
//
// One source of truth so every widget breathes the same way. Numbers
// here were sized for the actual rendered area of macOS desktop widgets
// (small ~165pt, medium ~344x163, large ~344x344) - not the dashboard
// which has a lot more room.
// =====================================================================

enum WidgetTokens {
    // Spacing
    static let outerPadding: CGFloat = 2
    static let sectionGap: CGFloat = 10
    static let inlineGap: CGFloat = 6

    // Typography
    static let header: Font = .system(size: 10, weight: .heavy)
    static let heroSmall: Font = .system(size: 30, weight: .semibold, design: .rounded)
    static let heroMedium: Font = .system(size: 26, weight: .semibold, design: .rounded)
    static let heroSubscript: Font = .system(size: 13, weight: .semibold, design: .rounded)
    static let body: Font = .system(size: 11, weight: .medium)
    static let bodyMono: Font = .system(size: 11, weight: .medium, design: .monospaced)
    static let micro: Font = .system(size: 9, weight: .medium)
    static let microMono: Font = .system(size: 10, weight: .medium, design: .monospaced)
    static let pillLabel: Font = .system(size: 10, weight: .bold, design: .rounded)

    // Tracking
    static let headerTracking: CGFloat = 0.5

    // Opacities
    static let primary: Double = 0.95
    static let secondary: Double = 0.55
    static let tertiary: Double = 0.35
    static let trackOpacity: Double = 0.07

    // Stroke widths
    static let ringSmall: CGFloat = 7
    static let ringMedium: CGFloat = 5
}

// MARK: - Shared header (logo + label + optional accessory)

struct WidgetHeader<Accessory: View>: View {
    let label: LocalizedStringKey
    let accessory: () -> Accessory

    init(_ label: LocalizedStringKey, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.label = label
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 5) {
            Image("WidgetLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
            Text(label)
                .font(WidgetTokens.header)
                .tracking(WidgetTokens.headerTracking)
                .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText).opacity(WidgetTokens.secondary))
                .textCase(.uppercase)
            Spacer(minLength: 0)
            accessory()
        }
    }
}

// MARK: - Shared zone pill

struct ZonePill: View {
    let zone: PacingZone

    var body: some View {
        let color = WidgetTheme.theme.pacingColor(for: zone)
        Text(zone.label)
            .font(WidgetTokens.pillLabel)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
    }
}

// MARK: - Hero number with inline % subscript

struct HeroPercent: View {
    let value: Int
    let font: Font
    let subscriptFont: Font

    init(_ value: Int, font: Font = WidgetTokens.heroSmall, subscriptFont: Font = WidgetTokens.heroSubscript) {
        self.value = value
        self.font = font
        self.subscriptFont = subscriptFont
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(value)")
                .font(font)
                .monospacedDigit()
                .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText))
            Text("%")
                .font(subscriptFont)
                .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText).opacity(WidgetTokens.tertiary))
        }
    }
}

// MARK: - Reset countdown row

struct ResetCountdownRow: View {
    let date: Date?
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        HStack(spacing: 5) {
            if alignment == .trailing { Spacer(minLength: 0) }
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText).opacity(WidgetTokens.tertiary))
            Text(formatResetTime(date))
                .font(WidgetTokens.microMono)
                .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText).opacity(WidgetTokens.secondary))
            if alignment == .leading { Spacer(minLength: 0) }
        }
    }
}

// =====================================================================
// MARK: - Session Ring (Small)
// =====================================================================

struct SessionRingWidgetView: View {
    let entry: UsageEntry

    private var theme: ThemeColors { WidgetTheme.theme }
    private var thresholds: UsageThresholds { WidgetTheme.thresholds }

    var body: some View {
        Group {
            if entry.error != nil, entry.usage == nil {
                ErrorContent(message: entry.error ?? String(localized: "error.nodata"))
            } else if let usage = entry.usage, let fiveHour = usage.fiveHour {
                ringContent(fiveHour, pacing: PacingCalculator.calculate(from: usage))
            } else {
                PlaceholderContent()
            }
        }
        .widgetURL(URL(string: "tokeneater://open"))
        .modifier(WidgetBackgroundModifier())
    }

    private func ringContent(_ bucket: UsageBucket, pacing: PacingResult?) -> some View {
        let pct = bucket.utilization
        let resetDate = bucket.resetsAtDate
        let smartColor = theme.smartGaugeNSColor(
            utilization: pct,
            resetDate: resetDate,
            windowDuration: 5 * 3600,
            thresholds: thresholds,
            profile: WidgetTheme.smartColorProfile
        )
        let gradient = WidgetTheme.smartColorEnabled
            ? theme.smartGaugeGradient(
                utilization: pct,
                resetDate: resetDate,
                windowDuration: 5 * 3600,
                thresholds: thresholds,
                profile: WidgetTheme.smartColorProfile
            )
            : theme.gaugeGradient(for: pct, thresholds: thresholds)

        return VStack(spacing: 0) {
            WidgetHeader("widget.session") {
                if let pacing {
                    Image(systemName: pacing.zone.iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.pacingColor(for: pacing.zone))
                }
            }
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .stroke(.white.opacity(WidgetTokens.trackOpacity), lineWidth: WidgetTokens.ringSmall)
                Circle()
                    .trim(from: 0, to: min(pct, 100) / 100)
                    .stroke(gradient, style: StrokeStyle(lineWidth: WidgetTokens.ringSmall, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(nsColor: smartColor).opacity(0.32), radius: 5)
                HeroPercent(Int(pct))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            Spacer(minLength: 8)
            ResetCountdownRow(date: resetDate)
        }
    }
}

// =====================================================================
// MARK: - Pacing Graph (Medium) - signature widget
//
// Reproduces the back-card of the Monitoring flippable hero card on
// the desktop. The graph plots utilization (Y) over elapsed window
// time (X), with the equilibrium diagonal as the "ideal pace" guide.
// The trajectory line shows where the user actually is, the filled
// zone visualizes the delta, and a glowing dot marks "now".
// =====================================================================

struct PacingGraphWidgetView: View {
    let entry: UsageEntry

    private var theme: ThemeColors { WidgetTheme.theme }

    var body: some View {
        Group {
            if entry.error != nil, entry.usage == nil {
                ErrorContent(message: entry.error ?? String(localized: "error.nodata"))
            } else if let usage = entry.usage,
                      let pacing = PacingCalculator.calculate(from: usage, bucket: .sevenDay),
                      let bucket = usage.sevenDay {
                graphContent(pacing: pacing, bucket: bucket)
            } else {
                PlaceholderContent()
            }
        }
        .widgetURL(URL(string: "tokeneater://open"))
        .modifier(WidgetBackgroundModifier())
    }

    private func graphContent(pacing: PacingResult, bucket: UsageBucket) -> some View {
        let zoneColor = theme.pacingColor(for: pacing.zone)
        let deltaText = "\(pacing.delta >= 0 ? "+" : "")\(Int(pacing.delta))%"

        return VStack(alignment: .leading, spacing: 10) {
            WidgetHeader("widget.pacing.title") {
                ZonePill(zone: pacing.zone)
            }

            // Hero delta + glyph
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(deltaText)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(zoneColor)
                Image(systemName: pacing.zone.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(zoneColor.opacity(0.85))
                    .baselineOffset(3)
                Spacer(minLength: 0)
                Text(pacing.message)
                    .font(WidgetTokens.body)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
                    .lineLimit(1)
            }

            // 4-zone pace spectrum with the NOW marker
            PaceSpectrumBar(delta: pacing.delta, currentZone: pacing.zone)
                .frame(height: 24)

            Spacer(minLength: 0)

            // Footer : weekly usage % + weekly reset countdown
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
                Text("\(Int(bucket.utilization))% used this week")
                    .font(WidgetTokens.microMono)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
                Spacer()
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
                Text(formatResetTime(bucket.resetsAtDate))
                    .font(WidgetTokens.microMono)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.secondary))
            }
        }
    }
}

// MARK: - Pace Spectrum Bar

/// Horizontal 4-zone bar (chill / on track / warning / hot) with a glowing
/// dot positioned where the user's current delta lands. Replaces the
/// equilibrium-diagonal chart that was unreadable at small deltas because
/// the trajectory line was visually identical to a horizontal line.
private struct PaceSpectrumBar: View {
    let delta: Double
    let currentZone: PacingZone

    var body: some View {
        let zones: [PacingZone] = [.chill, .onTrack, .warning, .hot]
        let position = positionFor(delta: delta)
        let theme = WidgetTheme.theme

        return ZStack(alignment: .leading) {
            // 4 zone segments side by side
            GeometryReader { proxy in
                let zoneWidth = (proxy.size.width - 6) / CGFloat(zones.count)
                HStack(spacing: 2) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                        let color = theme.pacingColor(for: zone)
                        let isCurrent = zone == currentZone
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color.opacity(isCurrent ? 0.20 : 0.08))
                            Image(systemName: zone.iconName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(color.opacity(isCurrent ? 0.85 : 0.35))
                        }
                        .frame(width: zoneWidth, height: 24)
                    }
                }

                // NOW marker - vertical needle that hovers above the active zone
                let dotColor = theme.pacingColor(for: currentZone)
                Circle()
                    .fill(Color(hex: theme.widgetBackground))
                    .frame(width: 13, height: 13)
                    .overlay(
                        Circle()
                            .fill(dotColor)
                            .frame(width: 9, height: 9)
                    )
                    .shadow(color: dotColor.opacity(0.65), radius: 5)
                    .position(
                        x: max(7, min(proxy.size.width - 7, proxy.size.width * position)),
                        y: 12
                    )
            }
        }
    }

    /// Map a delta in [-50, +50] to a normalized [0, 1] position on the bar :
    /// - chill zone occupies [0, 0.25]   -> delta in [-50, -m]
    /// - onTrack zone occupies [0.25, 0.50] -> delta in [-m, +m]
    /// - warning zone occupies [0.50, 0.75] -> delta in [+m, +2m]
    /// - hot zone occupies [0.75, 1.00]    -> delta in [+2m, +50]
    private func positionFor(delta: Double) -> Double {
        let m = 10.0
        let m2 = 20.0
        let cap = 50.0

        if delta <= -cap { return 0 }
        if delta >= cap { return 1 }
        if delta < -m {
            return 0.25 * (delta + cap) / (cap - m)
        }
        if delta <= m {
            return 0.25 + 0.25 * (delta + m) / (2 * m)
        }
        if delta <= m2 {
            return 0.50 + 0.25 * (delta - m) / m
        }
        return 0.75 + 0.25 * (delta - m2) / (cap - m2)
    }
}

// =====================================================================
// MARK: - History Sparkline (Large)
// =====================================================================

struct HistorySparklineWidgetView: View {
    let entry: UsageEntry

    private var theme: ThemeColors { WidgetTheme.theme }

    var body: some View {
        Group {
            if let totals = entry.lastWeekDailyTotals, !totals.isEmpty {
                sparklineContent(totals: totals)
            } else if entry.error != nil, entry.usage == nil {
                ErrorContent(message: entry.error ?? String(localized: "error.nodata"))
            } else {
                emptyStateContent
            }
        }
        .widgetURL(URL(string: "tokeneater://open?section=history"))
        .modifier(WidgetBackgroundModifier())
    }

    private func sparklineContent(totals: [Int]) -> some View {
        let total = totals.reduce(0, +)
        let peak = totals.max() ?? 1
        let todayIndex = totals.count - 1
        let todayValue = totals.last ?? 0
        let yesterdayValue = totals.count >= 2 ? totals[totals.count - 2] : 0
        let dayDelta = todayValue - yesterdayValue
        let calendar = Calendar.current
        let today = Date()

        return VStack(alignment: .leading, spacing: 12) {
            WidgetHeader("widget.history.title") {
                Text("widget.history.last7days")
                    .font(WidgetTokens.micro)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(formatTokens(total))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: theme.widgetText))
                    Text("widget.history.total")
                        .font(WidgetTokens.micro)
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
                        .textCase(.uppercase)
                        .tracking(0.3)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 3) {
                        Image(systemName: dayDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(dayDelta >= 0 ? "+" : "")\(formatTokens(abs(dayDelta)))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(dayDelta >= 0 ? Color(hex: "#FFB347") : Color(hex: "#32CE6A"))
                    Text("widget.history.vsYesterday")
                        .font(WidgetTokens.micro)
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
                        .textCase(.uppercase)
                        .tracking(0.3)
                }
            }

            // Bars
            GeometryReader { proxy in
                let barWidth: CGFloat = (proxy.size.width - CGFloat(totals.count - 1) * 6) / CGFloat(totals.count)
                let maxBarHeight = proxy.size.height - 16
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(totals.enumerated()), id: \.offset) { index, value in
                        let isToday = index == todayIndex
                        let normalized = peak > 0 ? CGFloat(value) / CGFloat(peak) : 0
                        let barHeight = maxBarHeight * normalized
                        let dayDate = calendar.date(byAdding: .day, value: index - todayIndex, to: today) ?? today

                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: theme.widgetText).opacity(0.05))
                                    .frame(height: maxBarHeight)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        isToday
                                            ? LinearGradient(
                                                colors: [Color(hex: "#FFB347"), Color(hex: "#FFCC80")],
                                                startPoint: .bottom,
                                                endPoint: .top
                                            )
                                            : LinearGradient(
                                                colors: [
                                                    Color(hex: theme.widgetText).opacity(0.40),
                                                    Color(hex: theme.widgetText).opacity(0.20)
                                                ],
                                                startPoint: .bottom,
                                                endPoint: .top
                                            )
                                    )
                                    .frame(height: max(2, barHeight))
                            }
                            .frame(width: barWidth)
                            Text(dayLabel(for: dayDate))
                                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                                .foregroundStyle(
                                    Color(hex: theme.widgetText)
                                        .opacity(isToday ? 0.85 : WidgetTokens.tertiary)
                                )
                        }
                    }
                }
            }

            if let refreshed = WidgetTheme.lastWeekTotalsRefreshedAt {
                let isStale = Date().timeIntervalSince(refreshed) > 36 * 3600
                HStack(spacing: 4) {
                    Circle()
                        .fill(isStale ? Color.orange.opacity(0.6) : Color.green.opacity(0.5))
                        .frame(width: 4, height: 4)
                    Text(isStale
                         ? String(localized: "widget.history.stale")
                         : String(format: String(localized: "widget.updated"), refreshed.relativeFormatted))
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
                }
            }
        }
    }

    private var emptyStateContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
            Text("widget.history.empty.title")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(hex: theme.widgetText).opacity(0.7))
                .multilineTextAlignment(.center)
            Text("widget.history.empty.body")
                .font(WidgetTokens.body)
                .foregroundStyle(Color(hex: theme.widgetText).opacity(WidgetTokens.tertiary))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: date).prefix(2))
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0fk", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

// =====================================================================
// MARK: - Pacing Glance (Small) - replaces the old PacingWidgetView
//
// Single big zone glyph in the center, large delta number underneath.
// Quieter than the old "ring + delta + ideal marker" composition.
// =====================================================================

struct PacingGlanceWidgetView: View {
    let entry: UsageEntry

    private var theme: ThemeColors { WidgetTheme.theme }

    var body: some View {
        Group {
            if let usage = entry.usage, let pacing = PacingCalculator.calculate(from: usage) {
                glanceContent(pacing)
            } else if entry.error != nil, entry.usage == nil {
                ErrorContent(message: entry.error ?? String(localized: "error.nodata"))
            } else {
                PlaceholderContent()
            }
        }
        .widgetURL(URL(string: "tokeneater://open"))
        .modifier(WidgetBackgroundModifier())
    }

    private func glanceContent(_ pacing: PacingResult) -> some View {
        let color = theme.pacingColor(for: pacing.zone)
        let sign = pacing.delta >= 0 ? "+" : ""

        return VStack(spacing: 0) {
            WidgetHeader("pacing.label")
            Spacer(minLength: 8)
            VStack(spacing: 6) {
                Image(systemName: pacing.zone.iconName)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.45), radius: 6)
                Text(pacing.zone.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                Text("\(sign)\(Int(pacing.delta))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: theme.widgetText))
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 8)
            ResetCountdownRow(date: pacing.resetDate)
        }
    }
}

// =====================================================================
// MARK: - PacingZone helpers (local to widget extension)
// =====================================================================

extension PacingZone {
    var iconName: String {
        switch self {
        case .chill:   return "leaf.fill"
        case .onTrack: return "bolt.fill"
        case .warning: return "hare.fill"
        case .hot:     return "flame.fill"
        }
    }
    var label: String {
        switch self {
        case .chill:   return String(localized: "pacing.zone.chill")
        case .onTrack: return String(localized: "pacing.zone.ontrack")
        case .warning: return String(localized: "pacing.zone.warning")
        case .hot:     return String(localized: "pacing.zone.hot")
        }
    }
}

// =====================================================================
// MARK: - Shared widget components
// =====================================================================

struct ErrorContent: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#F97316"), Color(hex: "#EF4444")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Text(message)
                .font(WidgetTokens.body)
                .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText).opacity(WidgetTokens.secondary))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct PlaceholderContent: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(.orange)
            Text("widget.loading")
                .font(WidgetTokens.body)
                .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText).opacity(WidgetTokens.tertiary))
        }
    }
}

// MARK: - WidgetTheme extension to expose lastWeekTotalsRefreshedAt

extension WidgetTheme {
    static var lastWeekTotalsRefreshedAt: Date? {
        SharedFileService().lastWeekTotalsRefreshedAt
    }
}

// MARK: - Time formatting helper (file-scope)

func formatResetTime(_ date: Date?) -> String {
    guard let date = date else { return "--" }
    let interval = date.timeIntervalSinceNow
    guard interval > 0 else { return String(localized: "widget.soon") }

    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60

    if hours >= 24 {
        let days = hours / 24
        return "\(days)d"
    }
    if hours > 0 {
        return "\(hours)h\(String(format: "%02d", minutes))"
    }
    return "\(minutes)m"
}

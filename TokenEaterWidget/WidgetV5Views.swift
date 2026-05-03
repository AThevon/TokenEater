import SwiftUI
import WidgetKit

// MARK: - Session Ring (Small)

/// Single big ring gauge for the 5h session window. Smart Color v2 drives
/// the ring color via HSB interpolation. Centered % in monospace + reset
/// countdown below + zone glyph in the bottom corner.
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
            HStack(spacing: 4) {
                Image("WidgetLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                Text("widget.session")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.5))
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                if let pacing {
                    Image(systemName: pacing.zone.iconName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.pacingColor(for: pacing.zone))
                }
            }
            .padding(.bottom, 6)

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.07), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: min(pct, 100) / 100)
                    .stroke(gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(nsColor: smartColor).opacity(0.35), radius: 6)
                VStack(spacing: 2) {
                    Text("\(Int(pct))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: theme.widgetText))
                    Text("%")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
                        .offset(y: -6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
                Text(formatResetTime(resetDate))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.6))
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .padding(2)
    }
}

// MARK: - Pacing Graph (Medium) - signature widget

/// Reproduces the back-card of the Monitoring flippable hero card on the
/// desktop. Shows the equilibrium diagonal (ideal pace), the user's actual
/// trajectory, and the filled delta zone between them.
struct PacingGraphWidgetView: View {
    let entry: UsageEntry

    private var theme: ThemeColors { WidgetTheme.theme }

    var body: some View {
        Group {
            if entry.error != nil, entry.usage == nil {
                ErrorContent(message: entry.error ?? String(localized: "error.nodata"))
            } else if let usage = entry.usage,
                      let pacing = PacingCalculator.calculate(from: usage),
                      let bucket = usage.fiveHour {
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
        // 5h session window. Compute elapsed fraction from the reset countdown.
        let windowDuration: TimeInterval = 5 * 3600
        let timeRemaining = bucket.resetsAtDate?.timeIntervalSinceNow ?? 0
        let elapsedFraction = min(1, max(0, (windowDuration - timeRemaining) / windowDuration))
        let actualFraction = min(1, max(0, pacing.actualUsage / 100))

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image("WidgetLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                Text("widget.pacing.title")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.55))
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Text(pacing.zone.label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(zoneColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(zoneColor.opacity(0.18), in: Capsule())
            }

            // Big delta number
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(deltaText)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(zoneColor)
                Image(systemName: pacing.zone.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(zoneColor)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)

            // The graph itself
            GeometryReader { proxy in
                ZStack {
                    // Grid lines (50% horizontal, 50% vertical)
                    Path { path in
                        let h = proxy.size.height
                        let w = proxy.size.width
                        path.move(to: CGPoint(x: 0, y: h * 0.5))
                        path.addLine(to: CGPoint(x: w, y: h * 0.5))
                        path.move(to: CGPoint(x: w * 0.5, y: 0))
                        path.addLine(to: CGPoint(x: w * 0.5, y: h))
                    }
                    .stroke(Color(hex: theme.widgetText).opacity(0.08), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))

                    // Equilibrium diagonal (ideal pace - bottom-left to top-right)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                    }
                    .stroke(Color(hex: theme.widgetText).opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    // Filled delta zone between equilibrium and actual
                    Path { path in
                        let w = proxy.size.width
                        let h = proxy.size.height
                        let xActual = w * elapsedFraction
                        let yActual = h - h * actualFraction
                        let yEquilibrium = h - h * elapsedFraction

                        path.move(to: CGPoint(x: 0, y: h))
                        path.addLine(to: CGPoint(x: xActual, y: yActual))
                        path.addLine(to: CGPoint(x: xActual, y: yEquilibrium))
                        path.closeSubpath()
                    }
                    .fill(zoneColor.opacity(0.20))

                    // Actual trajectory line
                    Path { path in
                        let w = proxy.size.width
                        let h = proxy.size.height
                        let xActual = w * elapsedFraction
                        let yActual = h - h * actualFraction
                        path.move(to: CGPoint(x: 0, y: h))
                        path.addLine(to: CGPoint(x: xActual, y: yActual))
                    }
                    .stroke(zoneColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                    // Now dot
                    Circle()
                        .fill(zoneColor)
                        .frame(width: 7, height: 7)
                        .position(
                            x: proxy.size.width * elapsedFraction,
                            y: proxy.size.height - proxy.size.height * actualFraction
                        )
                        .shadow(color: zoneColor.opacity(0.6), radius: 4)
                }
            }
            .padding(.top, 4)

            // Footer: usage % + reset countdown
            HStack {
                Text(String(format: "%d%% used", Int(bucket.utilization)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.55))
                Spacer()
                Image(systemName: "clock")
                    .font(.system(size: 9))
                Text(formatResetTime(bucket.resetsAtDate))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.55))
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - History Sparkline (Large) - killer widget

/// Last 7 days of token totals as a bar chart. Today highlighted in accent.
/// Sourced from `SharedFileService.lastWeekDailyTotals` (no JSONL re-parsing
/// from the widget process).
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

        return VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image("WidgetLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                Text("widget.history.title")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.55))
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Text("widget.history.last7days")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
            }

            // Stats row
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(formatTokens(total))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color(hex: theme.widgetText))
                    Text("widget.history.total")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
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
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
                        .textCase(.uppercase)
                        .tracking(0.3)
                }
            }

            // Bars
            GeometryReader { proxy in
                let barWidth: CGFloat = (proxy.size.width - CGFloat(totals.count - 1) * 6) / CGFloat(totals.count)
                let maxBarHeight = proxy.size.height - 14 // leave room for day labels
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(totals.enumerated()), id: \.offset) { index, value in
                        let isToday = index == todayIndex
                        let normalized = peak > 0 ? CGFloat(value) / CGFloat(peak) : 0
                        let barHeight = maxBarHeight * normalized
                        let dayDate = calendar.date(byAdding: .day, value: index - todayIndex, to: today) ?? today

                        VStack(spacing: 3) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: theme.widgetText).opacity(0.06))
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
                                                colors: [Color(hex: theme.widgetText).opacity(0.45), Color(hex: theme.widgetText).opacity(0.25)],
                                                startPoint: .bottom,
                                                endPoint: .top
                                            )
                                    )
                                    .frame(height: max(2, barHeight))
                            }
                            .frame(width: barWidth)
                            Text(dayLabel(for: dayDate))
                                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                                .foregroundStyle(Color(hex: theme.widgetText).opacity(isToday ? 0.9 : 0.4))
                        }
                    }
                }
            }

            // Footer freshness
            if let refreshed = WidgetTheme.lastWeekTotalsRefreshedAt {
                let isStale = Date().timeIntervalSince(refreshed) > 36 * 3600
                HStack(spacing: 4) {
                    Circle()
                        .fill(isStale ? Color.orange.opacity(0.6) : Color.green.opacity(0.5))
                        .frame(width: 4, height: 4)
                    Text(isStale
                         ? String(localized: "widget.history.stale")
                         : String(format: String(localized: "widget.updated"), refreshed.relativeFormatted))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(0.35))
                }
            }
        }
        .padding(2)
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
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: theme.widgetText).opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date).prefix(1).uppercased() + formatter.string(from: date).dropFirst().lowercased()
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

// MARK: - PacingZone helpers (local to widget extension)

private extension PacingZone {
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

// MARK: - Shared widget components

private struct ErrorContent: View {
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
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText).opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct PlaceholderContent: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(.orange)
            Text("widget.loading")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText).opacity(0.4))
        }
    }
}

// MARK: - WidgetTheme extension to expose lastWeekTotalsRefreshedAt

extension WidgetTheme {
    static var lastWeekTotalsRefreshedAt: Date? {
        SharedFileService().lastWeekTotalsRefreshedAt
    }
}

// MARK: - Time formatting helpers

private func formatResetTime(_ date: Date?) -> String {
    guard let date = date else { return "--" }
    let interval = date.timeIntervalSinceNow
    guard interval > 0 else { return String(localized: "widget.soon") }

    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60

    if hours > 24 {
        let days = hours / 24
        return "\(days)d"
    }
    if hours > 0 {
        return "\(hours)h\(String(format: "%02d", minutes))"
    }
    return "\(minutes)m"
}

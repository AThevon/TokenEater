import SwiftUI
import WidgetKit

/// Single SharedFileService instance shared across all widget views in a render pass.
/// Avoids creating 6+ instances (each calling migrateIfNeeded + disk read) per widget render.
enum WidgetTheme {
    private static let shared = SharedFileService()

    static var theme: ThemeColors { shared.theme }
    static var thresholds: UsageThresholds { shared.thresholds }
    static var smartColorEnabled: Bool { shared.smartColorEnabled }
    static var smartColorProfile: SmartColorProfile { shared.smartColorProfile }
}

// MARK: - Widget Background (macOS 13 compat)

struct WidgetBackgroundModifier: ViewModifier {
    var backgroundColor: Color = Color(hex: WidgetTheme.theme.widgetBackground).opacity(0.85)

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.containerBackground(for: .widget) {
                backgroundColor
            }
        } else {
            content.padding().background(backgroundColor)
        }
    }
}

// MARK: - Main Widget View

struct UsageWidgetView: View {
    let entry: UsageEntry

    @Environment(\.widgetFamily) var family
    private var theme: ThemeColors { WidgetTheme.theme }
    private var thresholds: UsageThresholds { WidgetTheme.thresholds }

    var body: some View {
        Group {
            if let error = entry.error, entry.usage == nil {
                errorView(error)
            } else if let usage = entry.usage {
                switch family {
                case .systemLarge:
                    largeUsageContent(usage)
                default:
                    mediumUsageContent(usage)
                }
            } else {
                placeholderView
            }
        }
        .widgetURL(URL(string: "tokeneater://open"))
        .modifier(WidgetBackgroundModifier())
    }

    // MARK: - Medium: Circular Charts

    private func mediumUsageContent(_ usage: UsageResponse) -> some View {
        VStack(spacing: 0) {
            WidgetHeader("widget.title.usage")
                .padding(.bottom, 14)

            // Circular gauges
            HStack(spacing: 0) {
                if let fiveHour = usage.fiveHour {
                    CircularUsageView(
                        label: String(localized: "widget.session"),
                        resetInfo: formatResetTime(fiveHour.resetsAtDate),
                        utilization: fiveHour.utilization,
                        resetDate: fiveHour.resetsAtDate,
                        windowDuration: 5 * 3600
                    )
                }
                if let sevenDay = usage.sevenDay {
                    CircularUsageView(
                        label: String(localized: "widget.weekly"),
                        resetInfo: formatResetDate(sevenDay.resetsAtDate),
                        utilization: sevenDay.utilization,
                        resetDate: sevenDay.resetsAtDate,
                        windowDuration: 7 * 86_400
                    )
                }
                if let pacing = PacingCalculator.calculate(from: usage) {
                    CircularPacingView(pacing: pacing)
                }
            }

            Spacer(minLength: 6)

            // Footer
            HStack {
                if let lastSync = entry.lastSync {
                    Text(String(format: String(localized: "widget.updated"), lastSync.relativeFormatted))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(0.3))
                } else {
                    Text(String(format: String(localized: "widget.updated"), entry.date.relativeFormatted))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(0.3))
                }
                Spacer()
                if entry.isStale {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Large: Expanded View

    private func largeUsageContent(_ usage: UsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader("widget.title.usage")

            // Bars - just the essentials per row : icon | label | % | reset
            if let fiveHour = usage.fiveHour {
                LargeUsageBarView(
                    icon: "timer",
                    label: String(localized: "widget.session"),
                    resetInfo: formatResetTime(fiveHour.resetsAtDate),
                    utilization: fiveHour.utilization,
                    resetDate: fiveHour.resetsAtDate,
                    windowDuration: 5 * 3600
                )
            }
            if let sevenDay = usage.sevenDay {
                LargeUsageBarView(
                    icon: "chart.bar.fill",
                    label: String(localized: "widget.weekly.full"),
                    resetInfo: formatResetDate(sevenDay.resetsAtDate),
                    utilization: sevenDay.utilization,
                    resetDate: sevenDay.resetsAtDate,
                    windowDuration: 7 * 86_400
                )
            }
            if let sonnet = usage.sevenDaySonnet {
                LargeUsageBarView(
                    icon: "wand.and.stars",
                    label: String(localized: "widget.sonnet"),
                    resetInfo: formatResetDate(sonnet.resetsAtDate),
                    utilization: sonnet.utilization,
                    resetDate: sonnet.resetsAtDate,
                    windowDuration: 7 * 86_400
                )
            }
            if let design = usage.sevenDayDesign {
                LargeUsageBarView(
                    icon: "paintbrush.pointed.fill",
                    label: String(localized: "widget.design"),
                    resetInfo: formatResetDate(design.resetsAtDate),
                    utilization: design.utilization,
                    resetDate: design.resetsAtDate,
                    windowDuration: 7 * 86_400
                )
            }

            // Subtle divider between usage bars and pacing bars
            Rectangle()
                .fill(Color(hex: theme.widgetText).opacity(0.07))
                .frame(height: 1)
                .padding(.vertical, 2)

            // Session pacing as a usage bar with an ideal marker
            if let sessionPacing = PacingCalculator.calculate(from: usage, bucket: .fiveHour) {
                LargePacingBarView(
                    icon: "timer",
                    label: String(localized: "widget.pacing.session"),
                    pacing: sessionPacing,
                    theme: theme
                )
            }
            // Weekly pacing as a usage bar with an ideal marker
            if let weeklyPacing = PacingCalculator.calculate(from: usage, bucket: .sevenDay) {
                LargePacingBarView(
                    icon: "chart.bar.fill",
                    label: String(localized: "widget.pacing.weekly"),
                    pacing: weeklyPacing,
                    theme: theme
                )
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
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
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color(hex: theme.widgetText).opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(.orange)
            Text("widget.loading")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
        }
    }

    // MARK: - Time Formatting

    private func formatResetTime(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return String(localized: "widget.soon") }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", minutes))"
        } else {
            return "\(minutes) min"
        }
    }

    private static let resetDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    private func formatResetDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        return Self.resetDateFormatter.string(from: date)
    }
}

// MARK: - Circular Usage View (Medium widget)

struct CircularUsageView: View {
    let label: String
    let resetInfo: String
    let utilization: Double
    var resetDate: Date? = nil
    var windowDuration: TimeInterval = 5 * 3600
    var smartEnabled: Bool = WidgetTheme.smartColorEnabled
    var smartProfile: SmartColorProfile = WidgetTheme.smartColorProfile
    var theme: ThemeColors = WidgetTheme.theme
    var thresholds: UsageThresholds = WidgetTheme.thresholds

    private var ringGradient: LinearGradient {
        if smartEnabled {
            return theme.smartGaugeGradient(
                utilization: utilization,
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: thresholds,
                profile: smartProfile
            )
        }
        return theme.gaugeGradient(for: utilization, thresholds: thresholds)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 4.5)

                Circle()
                    .trim(from: 0, to: min(utilization, 100) / 100)
                    .stroke(ringGradient, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(Int(utilization))%")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: theme.widgetText))
            }
            .frame(width: 50, height: 50)

            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.85))
                Text(resetInfo)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Circular Pacing View (Medium widget)

struct CircularPacingView: View {
    let pacing: PacingResult
    var theme: ThemeColors = WidgetTheme.theme

    private var ringColor: Color {
        theme.pacingColor(for: pacing.zone)
    }

    private var ringGradient: LinearGradient {
        theme.pacingGradient(for: pacing.zone)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 4.5)

                Circle()
                    .trim(from: 0, to: min(pacing.actualUsage, 100) / 100)
                    .stroke(ringGradient, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // Ideal marker on the ring
                let angle = (min(pacing.expectedUsage, 100) / 100) * 360 - 90
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 4, height: 4)
                    .offset(x: 25 * cos(angle * .pi / 180), y: 25 * sin(angle * .pi / 180))

                let sign = pacing.delta >= 0 ? "+" : ""
                Text("\(sign)\(Int(pacing.delta))%")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ringColor)
            }
            .frame(width: 50, height: 50)

            VStack(spacing: 2) {
                Text("pacing.label")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.85))
                Text(pacing.message)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(ringColor.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Large Pacing Bar (matches LargeUsageBarView style)

/// Same row layout as LargeUsageBarView (icon + label + value + bar) but the
/// progress bar shows the user's actual usage AND has a vertical needle
/// marker at the ideal position (elapsed fraction). Makes pacing read at a
/// glance : if the fill ends past the needle, you're ahead of pace ; if
/// short, you're behind.
struct LargePacingBarView: View {
    let icon: String
    let label: String
    let pacing: PacingResult
    let theme: ThemeColors

    var body: some View {
        let color = theme.pacingColor(for: pacing.zone)
        let sign = pacing.delta >= 0 ? "+" : ""
        let actualFraction = min(1, max(0, pacing.actualUsage / 100))
        let idealFraction = min(1, max(0, pacing.expectedUsage / 100))

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color.opacity(0.85))
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.9))

                Spacer()

                Text("\(sign)\(Int(pacing.delta))%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(.white.opacity(0.06))
                    // Fill - actual usage in pacing zone color
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.85), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: max(0, geo.size.width * actualFraction))
                    // Ideal needle - vertical line at expected position
                    Rectangle()
                        .fill(Color(hex: theme.widgetText).opacity(0.65))
                        .frame(width: 2, height: 9)
                        .position(x: geo.size.width * idealFraction, y: 2.5)
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Large Usage Bar View

struct LargeUsageBarView: View {
    let icon: String
    let label: String
    let resetInfo: String
    let utilization: Double
    var colorOverride: Color? = nil
    var displayText: String? = nil
    var resetDate: Date? = nil
    var windowDuration: TimeInterval = 5 * 3600
    var smartEnabled: Bool = WidgetTheme.smartColorEnabled
    var smartProfile: SmartColorProfile = WidgetTheme.smartColorProfile
    var theme: ThemeColors = WidgetTheme.theme
    var thresholds: UsageThresholds = WidgetTheme.thresholds

    private var barGradient: LinearGradient {
        if let color = colorOverride {
            return LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        }
        if smartEnabled {
            return theme.smartGaugeGradient(
                utilization: utilization,
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: thresholds,
                startPoint: .leading,
                endPoint: .trailing,
                profile: smartProfile
            )
        }
        return theme.gaugeGradient(for: utilization, thresholds: thresholds, startPoint: .leading, endPoint: .trailing)
    }

    private var accentColor: Color {
        if let color = colorOverride { return color }
        if smartEnabled {
            return theme.smartGaugeColor(
                utilization: utilization,
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: thresholds,
                profile: smartProfile
            )
        }
        return theme.gaugeColor(for: utilization, thresholds: thresholds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(0.85))
                    .frame(width: 14)

                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: theme.widgetText).opacity(0.9))

                Spacer()

                Text(displayText ?? "\(Int(utilization))%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accentColor)

                if !resetInfo.isEmpty {
                    Text(resetInfo)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: theme.widgetText).opacity(0.4))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(barGradient)
                        .frame(width: max(0, geo.size.width * min(utilization, 100) / 100))
                }
            }
            .frame(height: 5)
        }
    }
}

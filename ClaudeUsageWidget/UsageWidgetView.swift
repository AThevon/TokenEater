import SwiftUI
import WidgetKit

// MARK: - Widget Background (macOS 13 compat)

struct WidgetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.containerBackground(for: .widget) {
                Color.black.opacity(0.85)
            }
        } else {
            content.padding().background(Color.black.opacity(0.85))
        }
    }
}

// MARK: - Main Widget View

struct UsageWidgetView: View {
    let entry: UsageEntry

    @Environment(\.widgetFamily) var family

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
        .modifier(WidgetBackgroundModifier())
    }

    // MARK: - Medium: Circular Charts

    private func mediumUsageContent(_ usage: UsageResponse) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Image("WidgetLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 12, height: 12)
                Text("TokenEater")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if entry.isStale {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.bottom, 16)

            // Circular gauges
            HStack(spacing: 0) {
                if let fiveHour = usage.fiveHour {
                    CircularUsageView(
                        label: String(localized: "widget.session"),
                        resetInfo: formatResetTime(fiveHour.resetsAtDate),
                        utilization: fiveHour.utilization
                    )
                }
                if let sevenDay = usage.sevenDay {
                    CircularUsageView(
                        label: String(localized: "widget.weekly"),
                        resetInfo: formatResetDate(sevenDay.resetsAtDate),
                        utilization: sevenDay.utilization
                    )
                }
                if let pacing = PacingCalculator.calculate(from: usage) {
                    CircularPacingView(pacing: pacing)
                }
            }

            Spacer(minLength: 6)

            // Footer
            HStack {
                Text(String(format: String(localized: "widget.updated"), entry.date.relativeFormatted))
                    .font(.system(size: 8, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                if entry.isStale {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Large: Expanded View

    private func largeUsageContent(_ usage: UsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .center) {
                Image("WidgetLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                Text("TokenEater")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
                if entry.isStale {
                    HStack(spacing: 3) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 9))
                        Text("widget.offline")
                            .font(.system(size: 9, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.bottom, 8)

            // Session (5h)
            if let fiveHour = usage.fiveHour {
                LargeUsageBarView(
                    icon: "timer",
                    label: String(localized: "widget.session"),
                    subtitle: String(localized: "widget.session.subtitle"),
                    resetInfo: formatResetTime(fiveHour.resetsAtDate),
                    utilization: fiveHour.utilization
                )
            }

            // Weekly — All models
            if let sevenDay = usage.sevenDay {
                LargeUsageBarView(
                    icon: "chart.bar.fill",
                    label: String(localized: "widget.weekly.full"),
                    subtitle: String(localized: "widget.weekly.subtitle"),
                    resetInfo: formatResetDate(sevenDay.resetsAtDate),
                    utilization: sevenDay.utilization
                )
            }

            // Weekly — Sonnet
            if let sonnet = usage.sevenDaySonnet {
                LargeUsageBarView(
                    icon: "wand.and.stars",
                    label: String(localized: "widget.sonnet"),
                    subtitle: String(localized: "widget.sonnet.subtitle"),
                    resetInfo: formatResetDate(sonnet.resetsAtDate),
                    utilization: sonnet.utilization
                )
            }

            // Pacing
            if let pacing = PacingCalculator.calculate(from: usage) {
                LargeUsageBarView(
                    icon: "gauge.with.needle",
                    label: String(localized: "pacing.label"),
                    subtitle: pacing.message,
                    resetInfo: {
                        guard let r = pacing.resetDate, r.timeIntervalSinceNow > 0 else { return "" }
                        let d = Int(r.timeIntervalSinceNow) / 86400
                        let h = (Int(r.timeIntervalSinceNow) % 86400) / 3600
                        return d > 0 ? String(format: String(localized: "duration.days.hours"), d, h) : "\(h)h"
                    }(),
                    utilization: pacing.actualUsage,
                    colorOverride: {
                        switch pacing.zone {
                        case .chill: return Color(hex: "#22C55E")
                        case .onTrack: return Color(hex: "#0A84FF")
                        case .hot: return Color(hex: "#EF4444")
                        }
                    }(),
                    displayText: "\(pacing.delta >= 0 ? "+" : "")\(Int(pacing.delta))%"
                )
            }

            Spacer(minLength: 0)

            // Footer
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 1)
                .padding(.bottom, 4)

            HStack {
                Text(String(format: String(localized: "widget.updated"), entry.date.relativeFormatted))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                if entry.isStale {
                    HStack(spacing: 3) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 9))
                        Text("widget.offline")
                            .font(.system(size: 9, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.4))
                } else {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(.green.opacity(0.6))
                            .frame(width: 4, height: 4)
                        Text(String(localized: "widget.refresh.interval"))
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            }
        }
        .padding(4)
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
                .foregroundStyle(.white.opacity(0.6))
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
                .foregroundStyle(.white.opacity(0.4))
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

    private func formatResetDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Circular Usage View (Medium widget)

struct CircularUsageView: View {
    let label: String
    let resetInfo: String
    let utilization: Double

    private var ringGradient: LinearGradient {
        if utilization >= 85 {
            return LinearGradient(
                colors: [Color(hex: "#EF4444"), Color(hex: "#DC2626")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        } else if utilization >= 60 {
            return LinearGradient(
                colors: [Color(hex: "#F97316"), Color(hex: "#FB923C")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color(hex: "#22C55E"), Color(hex: "#4ADE80")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
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
                    .foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)

            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(.white.opacity(0.85))
                Text(resetInfo)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Circular Pacing View (Medium widget)

struct CircularPacingView: View {
    let pacing: PacingResult

    private var ringColor: Color {
        switch pacing.zone {
        case .chill: return Color(hex: "#22C55E")
        case .onTrack: return Color(hex: "#0A84FF")
        case .hot: return Color(hex: "#EF4444")
        }
    }

    private var ringGradient: LinearGradient {
        switch pacing.zone {
        case .chill:
            return LinearGradient(colors: [Color(hex: "#22C55E"), Color(hex: "#4ADE80")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .onTrack:
            return LinearGradient(colors: [Color(hex: "#0A84FF"), Color(hex: "#409CFF")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .hot:
            return LinearGradient(colors: [Color(hex: "#EF4444"), Color(hex: "#DC2626")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
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
                    .foregroundStyle(.white.opacity(0.85))
                Text(pacing.message)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(ringColor.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Large Usage Bar View

struct LargeUsageBarView: View {
    let icon: String
    let label: String
    let subtitle: String
    let resetInfo: String
    let utilization: Double
    var colorOverride: Color? = nil
    var displayText: String? = nil

    private var barGradient: LinearGradient {
        if let color = colorOverride {
            return LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        }
        if utilization >= 85 {
            return LinearGradient(
                colors: [Color(hex: "#EF4444"), Color(hex: "#DC2626")],
                startPoint: .leading, endPoint: .trailing
            )
        } else if utilization >= 60 {
            return LinearGradient(
                colors: [Color(hex: "#F97316"), Color(hex: "#FB923C")],
                startPoint: .leading, endPoint: .trailing
            )
        } else {
            return LinearGradient(
                colors: [Color(hex: "#22C55E"), Color(hex: "#4ADE80")],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    private var accentColor: Color {
        if let color = colorOverride { return color }
        if utilization >= 85 {
            return Color(hex: "#EF4444")
        } else if utilization >= 60 {
            return Color(hex: "#F97316")
        } else {
            return Color(hex: "#22C55E")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(accentColor.opacity(0.8))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.2)
                        .foregroundStyle(.white.opacity(0.9))
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(displayText ?? "\(Int(utilization))%")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accentColor)
                    Text(String(format: String(localized: "widget.reset"), resetInfo))
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barGradient)
                        .frame(width: max(0, geo.size.width * min(utilization, 100) / 100))
                }
            }
            .frame(height: 6)
        }
    }
}

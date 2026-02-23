import SwiftUI
import WidgetKit

struct PacingWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        Group {
            if let usage = entry.usage, let pacing = PacingCalculator.calculate(from: usage) {
                pacingContent(pacing)
            } else {
                placeholderContent
            }
        }
        .modifier(WidgetBackgroundModifier())
    }

    private func pacingContent(_ pacing: PacingResult) -> some View {
        VStack(spacing: 6) {
            // Header
            HStack(spacing: 4) {
                Circle()
                    .fill(colorForZone(pacing.zone))
                    .frame(width: 5, height: 5)
                Text("pacing.label")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
            }

            Spacer(minLength: 0)

            // Circular gauge
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 5)

                Circle()
                    .trim(from: 0, to: min(pacing.actualUsage, 100) / 100)
                    .stroke(gradientForZone(pacing.zone), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // Ideal marker
                let angle = (min(pacing.expectedUsage, 100) / 100) * 360 - 90
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 4, height: 4)
                    .offset(x: 28 * cos(angle * .pi / 180), y: 28 * sin(angle * .pi / 180))

                // Delta text
                let sign = pacing.delta >= 0 ? "+" : ""
                Text("\(sign)\(Int(pacing.delta))%")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(colorForZone(pacing.zone))
            }
            .frame(width: 60, height: 60)

            Spacer(minLength: 0)

            // Message
            Text(pacing.message)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(colorForZone(pacing.zone).opacity(0.8))
                .lineLimit(1)

            // Reset
            if let reset = pacing.resetDate, reset.timeIntervalSinceNow > 0 {
                Text(String(format: String(localized: "pacing.reset"), formatResetDate(reset)))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 2)
    }

    private var placeholderContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.3))
            Text("widget.loading")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func colorForZone(_ zone: PacingZone) -> Color {
        switch zone {
        case .chill: return Color(hex: "#32D74B")
        case .onTrack: return Color(hex: "#0A84FF")
        case .hot: return Color(hex: "#FF453A")
        }
    }

    private func gradientForZone(_ zone: PacingZone) -> LinearGradient {
        switch zone {
        case .chill:
            return LinearGradient(colors: [Color(hex: "#22C55E"), Color(hex: "#4ADE80")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .onTrack:
            return LinearGradient(colors: [Color(hex: "#0A84FF"), Color(hex: "#409CFF")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .hot:
            return LinearGradient(colors: [Color(hex: "#EF4444"), Color(hex: "#DC2626")], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func formatResetDate(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return String(localized: "widget.soon") }
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        if days > 0 {
            return String(format: String(localized: "duration.days.hours"), days, hours)
        }
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h\(String(format: "%02d", minutes))"
    }
}

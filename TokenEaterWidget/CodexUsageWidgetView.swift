import SwiftUI
import WidgetKit

struct CodexUsageWidgetView: View {
    let entry: CodexEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if !entry.isEnabled {
                ErrorContent(message: String(localized: "widget.codex.disabled"))
            } else if let usage = entry.usage {
                let windows = CodexWindowResolver.windows(in: usage, margin: entry.pacingMargin, schedule: WidgetTheme.pacingSchedule, now: entry.date)
                if windows.isEmpty {
                    ErrorContent(message: String(localized: "codex.test.noWindows"))
                } else {
                    content(usage: usage, windows: windows)
                }
            } else {
                ErrorContent(message: entry.error ?? String(localized: "error.nodata"))
            }
        }
        .widgetURL(URL(string: "tokeneater://open?section=monitoring"))
        .modifier(WidgetBackgroundModifier())
    }

    private func content(usage: CodexUsageResponse, windows: [CodexWindowSnapshot]) -> some View {
        VStack(spacing: 5) {
            WidgetHeader("Codex") {
                if let resets = usage.resetCreditsAvailable {
                    resetBadge(count: max(0, resets))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(family == .systemSmall ? Array(windows.prefix(1)) : windows) { window in
                    ring(window, limitReached: usage.isLimitReached)
                }
                if family == .systemMedium, let weekly = windows.first(where: { $0.kind == .weekly }), let pacing = weekly.pacing {
                    CircularPacingView(pacing: pacing)
                }
            }
            if usage.isLimitReached {
                Text("codex.limitReached")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.red)
            }
            if family == .systemMedium, let credits = usage.credits {
                if credits.overageLimitReached == true {
                    Text("codex.credits.cap")
                        .font(WidgetTokens.micro)
                        .foregroundStyle(.orange)
                } else if credits.hasCredits == true {
                    Text(credits.unlimited == true
                         ? String(localized: "codex.credits.unlimited")
                         : String(format: String(localized: "codex.credits.balance"), credits.balance ?? "—"))
                        .font(WidgetTokens.micro)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack {
                if let lastSync = entry.lastSync {
                    Text(String(format: String(localized: "widget.updated"), lastSync.relativeFormatted))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText).opacity(0.4))
                }
                Spacer(minLength: 0)

                if entry.isStale {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .accessibilityLabel(String(localized: "widget.codex.stale"))
                }
            }
        }
    }

    private func resetBadge(count: Int) -> some View {
        let tint = count > 0
            ? Color(hex: "#FFB347")
            : Color(hex: WidgetTheme.theme.widgetText).opacity(0.45)
        let label = count == 1
            ? String(localized: "widget.codex.reset.single")
            : String(format: String(localized: "widget.codex.resets"), count)
        return Text(label)
            .font(.system(size: family == .systemSmall ? 7.5 : 9, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(String(format: String(localized: "widget.codex.resets.accessibility"), count))
    }

    private func ring(_ window: CodexWindowSnapshot, limitReached: Bool) -> some View {
        let pct = limitReached ? 100 : window.pct
        let gradient = limitReached
            ? LinearGradient(colors: [.red], startPoint: .top, endPoint: .bottom)
            : GaugeColorResolver.gradient(
                mode: GaugeColorResolver.mode(smartColorEnabled: WidgetTheme.smartColorEnabled, windowDuration: window.windowDuration),
                utilization: pct, resetDate: window.resetDate, windowDuration: window.windowDuration,
                theme: WidgetTheme.theme, thresholds: WidgetTheme.thresholds,
                pacingMargin: entry.pacingMargin, now: entry.date,
                profile: WidgetTheme.smartColorProfile, startPoint: .topLeading, endPoint: .bottomTrailing
            )
        return VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(pct, 0), 100)) / 100)
                    .stroke(gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(pct)%")
                    .font(.system(size: family == .systemSmall ? 20 : 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText))
            }
            .frame(width: family == .systemSmall ? 64 : 50, height: family == .systemSmall ? 64 : 50)
            Text(window.label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText).opacity(0.85))
            Text(window.relativeReset)
                .font(.system(size: 8))
                .foregroundStyle(Color(hex: WidgetTheme.theme.widgetText).opacity(0.45))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex \(window.label)")
        .accessibilityValue("\(pct)%, \(window.relativeReset)")
    }
}

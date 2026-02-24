import SwiftUI
import WidgetKit

// MARK: - Popover View

struct MenuBarPopoverView: View {
    @Environment(UsageStore.self) private var usageStore
    @Environment(ThemeStore.self) private var themeStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TokenEater")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if usageStore.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Error banner
            if usageStore.hasError {
                errorBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            // Metrics
            VStack(spacing: 8) {
                metricRow(id: .fiveHour, label: String(localized: "metric.session"), pct: usageStore.fiveHourPct, reset: usageStore.fiveHourReset)
                metricRow(id: .sevenDay, label: String(localized: "metric.weekly"), pct: usageStore.sevenDayPct, reset: nil)
                metricRow(id: .sonnet, label: String(localized: "metric.sonnet"), pct: usageStore.sonnetPct, reset: nil)
            }
            .padding(.horizontal, 16)

            // Pacing section
            if let pacing = usageStore.pacingResult {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                settingsStore.toggleMetric(.pacing)
                            }
                        } label: {
                            Image(systemName: settingsStore.pinnedMetrics.contains(.pacing) ? "pin.fill" : "pin")
                                .font(.system(size: 9))
                                .foregroundStyle(settingsStore.pinnedMetrics.contains(.pacing) ? colorForZone(pacing.zone) : .white.opacity(0.2))
                        }
                        .buttonStyle(.plain)
                        .help(settingsStore.pinnedMetrics.contains(.pacing) ? Text(String(localized: "menubar.hide")) : Text(String(localized: "menubar.show")))

                        Text(String(localized: "pacing.label"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        let sign = pacing.delta >= 0 ? "+" : ""
                        Text("\(sign)\(Int(pacing.delta))%")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(colorForZone(pacing.zone))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(gradientForZone(pacing.zone))
                                .frame(width: max(0, geo.size.width * CGFloat(min(pacing.actualUsage, 100)) / 100), height: 4)

                            Rectangle()
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 2, height: 10)
                                .offset(x: geo.size.width * CGFloat(min(pacing.expectedUsage, 100)) / 100 - 1)
                        }
                    }
                    .frame(height: 10)

                    Text(pacing.message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(colorForZone(pacing.zone).opacity(0.8))
                }
                .padding(.horizontal, 16)
            }

            // Last update
            if let date = usageStore.lastUpdate {
                let formattedDate = date.formatted(.relative(presentation: .named))
                Text(String(format: String(localized: "menubar.updated"), formattedDate))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 10)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.top, 10)

            // Actions
            HStack(spacing: 0) {
                actionButton(icon: "arrow.clockwise", label: String(localized: "menubar.refresh")) {
                    Task { await usageStore.refresh(thresholds: themeStore.thresholds) }
                }
                actionButton(icon: "gear", label: String(localized: "menubar.settings")) {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: {
                        ($0.identifier?.rawValue ?? "").contains("settings")
                    }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        openWindow(id: "settings")
                    }
                }
                actionButton(icon: "power", label: String(localized: "menubar.quit")) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 260)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)))
        .onAppear {
            if settingsStore.hasCompletedOnboarding && usageStore.lastUpdate == nil {
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.reloadConfig(thresholds: themeStore.thresholds)
                usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
            }
        }
    }

    // MARK: - Helpers

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.5))
    }

    private func metricRow(id: MetricID, label: String, pct: Int, reset: String?) -> some View {
        let isPinned = settingsStore.pinnedMetrics.contains(id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        settingsStore.toggleMetric(id)
                    }
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 9))
                        .foregroundStyle(isPinned ? colorForPct(pct) : .white.opacity(0.2))
                        .rotationEffect(.degrees(isPinned ? 0 : 45))
                }
                .buttonStyle(.plain)
                .help(isPinned ? Text(String(localized: "menubar.hide")) : Text(String(localized: "menubar.show")))

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let reset = reset, !reset.isEmpty {
                    Text(String(format: String(localized: "metric.reset"), reset))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.25))
                }
                Text("\(pct)%")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(colorForPct(pct))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(gradientForPct(pct))
                        .frame(width: max(0, geo.size.width * CGFloat(pct) / 100), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch usageStore.errorState {
            case .tokenExpired:
                Label(String(localized: "error.banner.expired"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                Text(String(localized: "error.banner.expired.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            case .keychainLocked:
                Label(String(localized: "error.banner.keychain"), systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(String(localized: "error.banner.keychain.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            case .networkError(let message):
                Label(message, systemImage: "wifi.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func colorForZone(_ zone: PacingZone) -> Color {
        themeStore.current.pacingColor(for: zone)
    }

    private func gradientForZone(_ zone: PacingZone) -> LinearGradient {
        themeStore.current.pacingGradient(for: zone, startPoint: .leading, endPoint: .trailing)
    }

    private func colorForPct(_ pct: Int) -> Color {
        themeStore.current.gaugeColor(for: Double(pct), thresholds: themeStore.thresholds)
    }

    private func gradientForPct(_ pct: Int) -> LinearGradient {
        themeStore.current.gaugeGradient(for: Double(pct), thresholds: themeStore.thresholds, startPoint: .leading, endPoint: .trailing)
    }
}

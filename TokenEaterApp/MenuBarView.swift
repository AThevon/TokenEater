import SwiftUI

// MARK: - Popover View

struct MenuBarPopoverView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TokenEater")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                // Plan badge
                if usageStore.planType != .unknown {
                    Text(usageStore.planType.rawValue.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.3))
                        .clipShape(Capsule())
                }
                Spacer()
                if usageStore.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
                Button {
                    NotificationCenter.default.post(name: .openDashboard, object: nil)
                } label: {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(Text("Dashboard"))
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

            // Mini hero ring — Session (fiveHour)
            heroRing
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Satellite rings — Weekly + Sonnet
            satelliteRings
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            // Pacing section
            if let pacing = usageStore.pacingResult {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

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
                                .rotationEffect(.degrees(settingsStore.pinnedMetrics.contains(.pacing) ? 0 : 45))
                        }
                        .buttonStyle(.plain)
                        .help(settingsStore.pinnedMetrics.contains(.pacing) ? Text(String(localized: "menubar.hide")) : Text(String(localized: "menubar.show")))

                        Text(String(localized: "pacing.label"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        let sign = pacing.delta >= 0 ? "+" : ""
                        GlowText(
                            "\(sign)\(Int(pacing.delta))%",
                            font: .system(size: 13, weight: .black, design: .rounded),
                            color: colorForZone(pacing.zone),
                            glowRadius: 3
                        )
                    }

                    PacingBar(
                        actual: pacing.actualUsage,
                        expected: pacing.expectedUsage,
                        zone: pacing.zone,
                        gradient: gradientForZone(pacing.zone),
                        compact: true
                    )

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
        .frame(width: 300)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)))
        .onAppear {
            if settingsStore.hasCompletedOnboarding {
                if usageStore.lastUpdate == nil {
                    usageStore.proxyConfig = settingsStore.proxyConfig
                    usageStore.reloadConfig(thresholds: themeStore.thresholds)
                    usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
                } else {
                    Task { await usageStore.refresh(thresholds: themeStore.thresholds) }
                }
            }
        }
    }

    // MARK: - Hero Ring (Session)

    private var heroRing: some View {
        let pct = usageStore.fiveHourPct
        let isPinned = settingsStore.pinnedMetrics.contains(.fiveHour)
        return ZStack {
            RingGauge(
                percentage: pct,
                gradient: gradientForPct(pct),
                size: 100,
                glowColor: colorForPct(pct),
                glowRadius: 6
            )

            VStack(spacing: 2) {
                GlowText(
                    "\(pct)%",
                    font: .system(size: 24, weight: .black, design: .rounded),
                    color: colorForPct(pct),
                    glowRadius: 4
                )
                Text(String(localized: "metric.session"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    settingsStore.toggleMetric(.fiveHour)
                }
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 9))
                    .foregroundStyle(isPinned ? colorForPct(pct) : .white.opacity(0.2))
                    .rotationEffect(.degrees(isPinned ? 0 : 45))
            }
            .buttonStyle(.plain)
            .help(isPinned ? Text(String(localized: "menubar.hide")) : Text(String(localized: "menubar.show")))
            .offset(x: 4, y: 4)
        }
        .overlay(alignment: .bottom) {
            if let reset = usageStore.fiveHourReset, !reset.isEmpty {
                Text(String(format: String(localized: "metric.reset"), reset))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.25))
                    .offset(y: 18)
            }
        }
        .padding(.bottom, usageStore.fiveHourReset != nil ? 14 : 0)
    }

    // MARK: - Satellite Rings (Weekly + Sonnet)

    private var satelliteRings: some View {
        HStack(spacing: 32) {
            satelliteRingItem(
                id: .sevenDay,
                label: String(localized: "metric.weekly"),
                pct: usageStore.sevenDayPct
            )
            satelliteRingItem(
                id: .sonnet,
                label: String(localized: "metric.sonnet"),
                pct: usageStore.sonnetPct
            )
        }
    }

    private func satelliteRingItem(id: MetricID, label: String, pct: Int) -> some View {
        let isPinned = settingsStore.pinnedMetrics.contains(id)
        return VStack(spacing: 4) {
            ZStack {
                RingGauge(
                    percentage: pct,
                    gradient: gradientForPct(pct),
                    size: 40,
                    glowColor: colorForPct(pct),
                    glowRadius: 3
                )
                GlowText(
                    "\(pct)%",
                    font: .system(size: 10, weight: .black, design: .rounded),
                    color: colorForPct(pct),
                    glowRadius: 2
                )
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    settingsStore.toggleMetric(id)
                }
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 8))
                    .foregroundStyle(isPinned ? colorForPct(pct) : .white.opacity(0.2))
                    .rotationEffect(.degrees(isPinned ? 0 : 45))
            }
            .buttonStyle(.plain)
            .help(isPinned ? Text(String(localized: "menubar.hide")) : Text(String(localized: "menubar.show")))
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

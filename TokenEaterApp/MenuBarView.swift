import SwiftUI

// MARK: - Popover View

struct MenuBarPopoverView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var lastUpdateText = ""

    private let updateTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if usageStore.planType != .unknown {
                    Text(usageStore.planType.displayLabel)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(usageStore.planType.badgeColor.opacity(0.3))
                        .clipShape(Capsule())
                }
                Spacer()
                if usageStore.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)

            // Error banner
            if usageStore.hasError {
                errorBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            // Mini hero ring — Session (fiveHour)
            heroRing
                .padding(.horizontal, 16)
                .padding(.bottom, 20)

            // Satellite rings — Weekly + Sonnet
            satelliteRings
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            // Pacing section
            if let pacing = usageStore.pacingResult {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            settingsStore.toggleMetric(.pacing)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: settingsStore.pinnedMetrics.contains(.pacing) ? "pin.fill" : "pin")
                                .font(.system(size: 7))
                                .foregroundStyle(settingsStore.pinnedMetrics.contains(.pacing) ? colorForZone(pacing.zone) : .white.opacity(0.2))
                                .rotationEffect(.degrees(settingsStore.pinnedMetrics.contains(.pacing) ? 0 : 45))
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
                    }
                    .buttonStyle(.plain)
                    .help(settingsStore.pinnedMetrics.contains(.pacing) ? Text(String(localized: "menubar.hide")) : Text(String(localized: "menubar.show")))

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

            // Watchers toggle
            watchersToggle
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // Last update
            if !lastUpdateText.isEmpty {
                Text(String(format: String(localized: "menubar.updated"), lastUpdateText))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 10)
            }

            // Footer
            VStack(spacing: 8) {
                // CTA — Open TokenEater
                Button {
                    NotificationCenter.default.post(name: .openDashboard, object: nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 8))
                        Text("Open TokenEater")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                // Refresh · Quit
                HStack(spacing: 4) {
                    Button(String(localized: "menubar.refresh")) {
                        Task { await usageStore.refresh(thresholds: themeStore.thresholds, force: true) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))

                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))

                    Button(String(localized: "menubar.quit")) {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 300)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)))
        .onAppear {
            refreshLastUpdateText()
            // Single refresh on appear — auto-refresh lifecycle is owned by StatusBarController
            if settingsStore.hasCompletedOnboarding {
                Task { await usageStore.refresh(thresholds: themeStore.thresholds) }
            }
        }
        .onReceive(updateTimer) { _ in
            refreshLastUpdateText()
        }
        .onChange(of: usageStore.lastUpdate) { _, _ in
            refreshLastUpdateText()
        }
    }

    private func refreshLastUpdateText() {
        if let date = usageStore.lastUpdate {
            lastUpdateText = date.formatted(.relative(presentation: .named))
        }
    }

    // MARK: - Hero Ring (Session)

    private var heroRing: some View {
        let pct = usageStore.fiveHourPct
        let isPinned = settingsStore.pinnedMetrics.contains(.fiveHour)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                settingsStore.toggleMetric(.fiveHour)
            }
        } label: {
            VStack(spacing: 10) {
                ZStack {
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

                HStack(spacing: 3) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 7))
                        .foregroundStyle(isPinned ? colorForPct(pct) : .white.opacity(0.2))
                        .rotationEffect(.degrees(isPinned ? 0 : 45))
                    if !usageStore.fiveHourReset.isEmpty {
                        Text(String(format: String(localized: "metric.reset"), usageStore.fiveHourReset))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .help(isPinned ? Text(String(localized: "menubar.hide")) : Text(String(localized: "menubar.show")))
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
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                settingsStore.toggleMetric(id)
            }
        } label: {
            VStack(spacing: 4) {
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
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 7))
                    .foregroundStyle(isPinned ? colorForPct(pct) : .white.opacity(0.2))
                    .rotationEffect(.degrees(isPinned ? 0 : 45))
            }
        }
        .buttonStyle(.plain)
        .help(isPinned ? Text(String(localized: "menubar.hide")) : Text(String(localized: "menubar.show")))
    }

    // MARK: - Watchers Toggle

    private var watchersToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settingsStore.overlayEnabled.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: settingsStore.overlayEnabled ? "eye.fill" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(settingsStore.overlayEnabled ? .blue : .white.opacity(0.25))
                    .frame(width: 18)

                Text(String(localized: "sidebar.agentWatchers"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                Spacer()

                Circle()
                    .fill(settingsStore.overlayEnabled ? .blue : .white.opacity(0.12))
                    .frame(width: 6, height: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(settingsStore.overlayEnabled ? .blue.opacity(0.08) : .white.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

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

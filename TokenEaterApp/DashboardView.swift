import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ZStack {
            // Animated background
            AnimatedGradient(baseColors: backgroundColors)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                dashboardHeader
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 24) {
                        // Hero: Session ring
                        heroSection

                        // Satellite rings: Weekly + model-specific
                        satelliteSection

                        // Pacing
                        if let pacing = usageStore.pacingResult {
                            pacingSection(pacing: pacing)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(width: 650, height: 550)
        .onAppear {
            if settingsStore.hasCompletedOnboarding, usageStore.lastUpdate == nil {
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.reloadConfig(thresholds: themeStore.thresholds)
                usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
            } else {
                Task { await usageStore.refresh(thresholds: themeStore.thresholds) }
            }
        }
    }

    // MARK: - Background colors based on pacing zone

    private var backgroundColors: [Color] {
        switch usageStore.pacingZone {
        case .chill:
            return [Color(red: 0.04, green: 0.04, blue: 0.10), Color(red: 0.04, green: 0.08, blue: 0.16)]
        case .onTrack:
            return [Color(red: 0.04, green: 0.04, blue: 0.10), Color(red: 0.08, green: 0.08, blue: 0.16)]
        case .hot:
            return [Color(red: 0.10, green: 0.04, blue: 0.04), Color(red: 0.16, green: 0.08, blue: 0.08)]
        }
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        HStack {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("TokenEater")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            if usageStore.planType != .unknown {
                Text(usageStore.planType.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(planBadgeColor.opacity(0.3))
                    .clipShape(Capsule())
            }

            if let tier = usageStore.rateLimitTier {
                Text(tier.replacingOccurrences(of: "default_claude_", with: "").uppercased())
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            if usageStore.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }

            if let date = usageStore.lastUpdate {
                Text(String(format: String(localized: "menubar.updated"), date.formatted(.relative(presentation: .named))))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Button {
                Task { await usageStore.refresh(thresholds: themeStore.thresholds) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private var planBadgeColor: Color {
        switch usageStore.planType {
        case .max: return .purple
        case .pro: return .blue
        case .free: return .gray
        case .unknown: return .clear
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        ZStack {
            // Particles
            ParticleField(
                particleCount: 25,
                speed: Double(usageStore.fiveHourPct) / 100.0,
                color: gaugeColor(for: usageStore.fiveHourPct),
                radius: 130
            )
            .frame(width: 280, height: 280)

            VStack(spacing: 4) {
                RingGauge(
                    percentage: usageStore.fiveHourPct,
                    gradient: gaugeGradient(for: usageStore.fiveHourPct),
                    size: 200,
                    glowColor: gaugeColor(for: usageStore.fiveHourPct),
                    glowRadius: 8
                )
                .overlay {
                    VStack(spacing: 2) {
                        GlowText(
                            "\(usageStore.fiveHourPct)%",
                            font: .system(size: 42, weight: .black, design: .rounded),
                            color: gaugeColor(for: usageStore.fiveHourPct),
                            glowRadius: 6
                        )
                        Text(String(localized: "metric.session"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        if !usageStore.fiveHourReset.isEmpty {
                            Text(String(format: String(localized: "metric.reset"), usageStore.fiveHourReset))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Satellite Rings

    private var satelliteSection: some View {
        HStack(spacing: 20) {
            satelliteRing(label: String(localized: "metric.weekly"), pct: usageStore.sevenDayPct)
            satelliteRing(label: String(localized: "metric.sonnet"), pct: usageStore.sonnetPct)
            if usageStore.hasOpus {
                satelliteRing(label: "Opus", pct: usageStore.opusPct)
            }
            if usageStore.hasCowork {
                satelliteRing(label: "Cowork", pct: usageStore.coworkPct)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func satelliteRing(label: String, pct: Int) -> some View {
        VStack(spacing: 6) {
            RingGauge(
                percentage: pct,
                gradient: gaugeGradient(for: pct),
                size: 80,
                glowColor: gaugeColor(for: pct),
                glowRadius: 4
            )
            .overlay {
                GlowText(
                    "\(pct)%",
                    font: .system(size: 18, weight: .black, design: .rounded),
                    color: gaugeColor(for: pct),
                    glowRadius: 3
                )
            }

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Pacing Section

    private func pacingSection(pacing: PacingResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "pacing.label"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                let sign = pacing.delta >= 0 ? "+" : ""
                GlowText(
                    "\(sign)\(Int(pacing.delta))%",
                    font: .system(size: 20, weight: .black, design: .rounded),
                    color: themeStore.current.pacingColor(for: pacing.zone),
                    glowRadius: 4
                )
            }

            PacingBar(
                actual: pacing.actualUsage,
                expected: pacing.expectedUsage,
                zone: pacing.zone,
                gradient: themeStore.current.pacingGradient(for: pacing.zone, startPoint: .leading, endPoint: .trailing)
            )

            Text(pacing.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(themeStore.current.pacingColor(for: pacing.zone).opacity(0.8))

            if let resetDate = pacing.resetDate {
                let diff = resetDate.timeIntervalSinceNow
                if diff > 0 {
                    let days = Int(diff) / 86400
                    let hours = (Int(diff) % 86400) / 3600
                    let resetText = days > 0
                        ? String(format: String(localized: "dashboard.pacing.reset.days"), days, hours)
                        : String(format: String(localized: "dashboard.pacing.reset.hours"), hours)
                    Text(resetText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Theme Helpers

    private func gaugeColor(for pct: Int) -> Color {
        themeStore.current.gaugeColor(for: Double(pct), thresholds: themeStore.thresholds)
    }

    private func gaugeGradient(for pct: Int) -> LinearGradient {
        themeStore.current.gaugeGradient(for: Double(pct), thresholds: themeStore.thresholds, startPoint: .leading, endPoint: .trailing)
    }
}

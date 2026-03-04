import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var isVisible = false
    @State private var lastUpdateText = ""

    var body: some View {
        ZStack {
            // Animated background
            if settingsStore.animatedGradientEnabled {
                AnimatedGradient(baseColors: backgroundColors, isActive: isVisible)
                    .ignoresSafeArea()
            } else {
                backgroundColors.first
                    .ignoresSafeArea()
            }

            HStack(spacing: 0) {
                // Left column (~55%) — Metrics
                leftColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right column (~45%) — Context
                rightColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(24)
        }
        .onAppear {
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
        .task {
            refreshLastUpdateText()
            if settingsStore.hasCompletedOnboarding {
                await usageStore.refresh(thresholds: themeStore.thresholds)
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                refreshLastUpdateText()
            }
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

    // MARK: - Background colors tinted by 5h gauge state

    private var backgroundColors: [Color] {
        let base = Color(red: 0.10, green: 0.10, blue: 0.12)
        let stateColor = themeStore.current.gaugeColor(
            for: Double(usageStore.fiveHourPct),
            thresholds: themeStore.thresholds
        )
        let tinted = blend(stateColor, into: base, amount: 0.15)
        return [base, tinted]
    }

    private func blend(_ accent: Color, into base: Color, amount: Double) -> Color {
        let a = NSColor(accent).usingColorSpace(.sRGB) ?? NSColor(accent)
        let b = NSColor(base).usingColorSpace(.sRGB) ?? NSColor(base)
        return Color(
            red: b.redComponent + (a.redComponent - b.redComponent) * amount,
            green: b.greenComponent + (a.greenComponent - b.greenComponent) * amount,
            blue: b.blueComponent + (a.blueComponent - b.blueComponent) * amount
        )
    }

    // MARK: - Left Column (Metrics)

    private var leftColumn: some View {
        VStack(spacing: 16) {
            Spacer()

            // Hero ring
            heroSection

            // Satellite rings
            satelliteSection

            Spacer()
        }
    }

    // MARK: - Right Column (Context)

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            dashboardHeader

            Spacer()

            // Profile card
            if usageStore.planType != .unknown {
                profileCard
            }

            // Pacing card
            if let pacing = usageStore.pacingResult {
                pacingCard(pacing: pacing)
            }

            Spacer()
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
                Text(usageStore.planType.displayLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
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

            if !lastUpdateText.isEmpty {
                Text(String(format: String(localized: "menubar.updated"), lastUpdateText))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Button {
                Task { await usageStore.refresh(thresholds: themeStore.thresholds, force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        ZStack {
            if settingsStore.particlesEnabled {
                ParticleField(
                    particleCount: 25,
                    speed: Double(usageStore.fiveHourPct) / 100.0,
                    color: gaugeColor(for: usageStore.fiveHourPct),
                    radius: 130,
                    isActive: isVisible
                )
                .frame(width: 280, height: 280)
            }

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

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let tier = usageStore.rateLimitTier {
                HStack(spacing: 6) {
                    Text(String(localized: "dashboard.tier"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(tier.formattedRateLimitTier)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            if let org = usageStore.organizationName {
                HStack(spacing: 6) {
                    Text(String(localized: "dashboard.org"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(org)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Pacing Card

    private func pacingCard(pacing: PacingResult) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Theme Helpers

    private func gaugeColor(for pct: Int) -> Color {
        themeStore.current.gaugeColor(for: Double(pct), thresholds: themeStore.thresholds)
    }

    private func gaugeGradient(for pct: Int) -> LinearGradient {
        themeStore.current.gaugeGradient(for: Double(pct), thresholds: themeStore.thresholds, startPoint: .leading, endPoint: .trailing)
    }
}

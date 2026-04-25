import SwiftUI

/// Cockpit-style dashboard - one wide "command strip" hero, a dense grid of
/// metric tiles, two "signal" pacing cards, and a footer status row. Premium
/// app aesthetic (Linear / Raycast). No continuous animation: springs on
/// value changes only so the dashboard is zero-CPU at rest.
struct DashboardView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var isVisible = false
    @State private var lastUpdateText = ""

    var body: some View {
        ZStack {
            if settingsStore.animatedGradientEnabled {
                AnimatedGradient(baseColors: backgroundColors, isActive: isVisible)
                    .ignoresSafeArea()
            } else {
                backgroundColors.first
                    .ignoresSafeArea()
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    dashboardHeader
                    heroCommandStrip
                    metricsGrid
                    pacingSignals
                    if let extra = usageStore.extraUsage, extra.isEnabled {
                        extraUsageCard(extra)
                    }
                    footerStatus
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task {
            refreshLastUpdateText()
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
        }
    }

    // MARK: - Hero Command Strip

    /// Wide horizontal "command strip" showing the dominant metric: session
    /// label on the left, a huge glowing number, a ticked progress track, and
    /// the reset countdown. A large ring on the right anchors the visual.
    private var heroCommandStrip: some View {
        let pct = usageStore.fiveHourPct
        let color = gaugeColor(for: pct)
        return HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                heroLabelRow(color: color)
                heroValueRow(pct: pct, color: color)
                heroProgressTrack(pct: pct, color: color)
                heroResetRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            heroRing(pct: pct, color: color)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background(heroBackground(color: color))
    }

    private func heroLabelRow(color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color).frame(width: 7, height: 7)
                Circle().fill(color).frame(width: 7, height: 7).blur(radius: 5)
            }
            Text(String(localized: "dashboard.hero.session.label"))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))
                .tracking(2)
        }
    }

    private func heroValueRow(pct: Int, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            GlowText(
                "\(pct)",
                font: .system(size: 88, weight: .black, design: .rounded),
                color: color,
                glowRadius: 12
            )
            Text("%")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(color.opacity(0.55))
                .baselineOffset(6)
        }
    }

    private func heroProgressTrack(pct: Int, color: Color) -> some View {
        let clamped = CGFloat(min(max(pct, 0), 100)) / 100
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 5)
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(LinearGradient(
                        colors: [color.opacity(0.65), color],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(0, geo.size.width * clamped), height: 5)
                    .shadow(color: color.opacity(0.55), radius: 5)
            }
        }
        .frame(height: 5)
        .frame(maxWidth: 400)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: pct)
    }

    private var heroResetRow: some View {
        // Icon center-aligned visually, the two texts baseline-aligned to
        // avoid the 10pt / 13pt font mismatch visible when using default
        // HStack centering.
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(localized: "dashboard.hero.resetsIn").uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1.5)
                if !usageStore.fiveHourReset.isEmpty {
                    Text(usageStore.fiveHourReset)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Text("-")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private func heroRing(pct: Int, color: Color) -> some View {
        // Zone glyph - shape conveys the pacing zone (leaf / bolt / flame) and
        // colour carries the pacing zone tint, distinct from the ring's gauge
        // colour. On purpose: the ring answers "how much have I used?" and the
        // glyph answers "how's my rhythm?" - two dimensions, two palettes.
        let zone = usageStore.fiveHourPacing?.zone
        let glyphColor = zone.map { themeStore.current.pacingColor(for: $0) } ?? color

        return ZStack {
            RadialGradient(
                colors: [color.opacity(0.24), color.opacity(0.06), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 90
            )
            .frame(width: 200, height: 200)
            .blur(radius: 16)
            .allowsHitTesting(false)

            RingGauge(
                percentage: pct,
                gradient: gaugeGradient(for: pct),
                size: 140,
                glowColor: color,
                glowRadius: 9
            )

            Image(systemName: zoneGlyph(for: zone))
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(glyphColor)
                .shadow(color: glyphColor.opacity(0.55), radius: 10)
                .shadow(color: glyphColor.opacity(0.35), radius: 18)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: zone)
        }
        .frame(width: 160, height: 160)
    }

    private func zoneGlyph(for zone: PacingZone?) -> String {
        switch zone {
        case .chill: return "leaf.fill"
        case .onTrack: return "bolt.fill"
        case .hot: return "flame.fill"
        case nil: return "sparkles"
        }
    }

    private func heroBackground(color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [color.opacity(0.11), Color.white.opacity(0.025)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: 20)
                .stroke(LinearGradient(
                    colors: [color.opacity(0.32), color.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 0.9)
        }
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        HStack(spacing: 10) {
            metricTile(
                label: String(localized: "metric.weekly"),
                pct: usageStore.sevenDayPct,
                resetText: usageStore.sevenDayReset,
                icon: "calendar"
            )
            metricTile(
                label: String(localized: "metric.sonnet"),
                pct: usageStore.sonnetPct,
                resetText: usageStore.sonnetReset.isEmpty ? nil : usageStore.sonnetReset,
                icon: "text.quote"
            )
            if usageStore.hasDesign {
                metricTile(
                    label: String(localized: "metric.design"),
                    pct: usageStore.designPct,
                    resetText: usageStore.designReset.isEmpty ? nil : usageStore.designReset,
                    icon: "paintbrush.pointed.fill"
                )
            }
            if usageStore.hasOpus {
                metricTile(
                    label: "Opus",
                    pct: usageStore.opusPct,
                    resetText: nil,
                    icon: "brain.head.profile"
                )
            }
            if usageStore.hasCowork {
                metricTile(
                    label: "Cowork",
                    pct: usageStore.coworkPct,
                    resetText: nil,
                    icon: "person.2.fill"
                )
            }
        }
    }

    private func metricTile(label: String, pct: Int, resetText: String?, icon: String) -> some View {
        let color = gaugeColor(for: pct)
        let clamped = CGFloat(min(max(pct, 0), 100)) / 100
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color.opacity(0.75))
                    .frame(width: 14)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .tracking(1.2)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                GlowText(
                    "\(pct)",
                    font: .system(size: 32, weight: .black, design: .rounded),
                    color: color,
                    glowRadius: 4
                )
                Text("%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(color.opacity(0.6))
                    .baselineOffset(3)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(LinearGradient(
                            colors: [color.opacity(0.65), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * clamped, height: 3)
                        .shadow(color: color.opacity(0.5), radius: 3)
                }
            }
            .frame(height: 3)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: pct)

            // Reserved caption row. When present, uses the same "icon + label
            // + value" layout as the hero reset row so the two feel like
            // siblings - just smaller. Tiles without reset info keep the row
            // blank so every tile has the exact same height.
            Group {
                if let resetText, !resetText.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(String(localized: "dashboard.hero.resetsIn").uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                                .tracking(1)
                            Text(resetText)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                } else {
                    Text(" ")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.clear)
                }
            }
            .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tileBackground(color: color))
    }

    private func tileBackground(color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.028))
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.18), lineWidth: 0.8)
        }
    }

    // MARK: - Pacing Signals

    private var pacingSignals: some View {
        HStack(spacing: 10) {
            if let pacing = usageStore.fiveHourPacing {
                pacingSignal(
                    pacing: pacing,
                    label: String(localized: "pacing.session.label"),
                    icon: "clock.fill"
                )
                .frame(maxWidth: .infinity)
            }
            if let pacing = usageStore.pacingResult {
                pacingSignal(
                    pacing: pacing,
                    label: String(localized: "pacing.weekly.label"),
                    icon: "calendar.badge.clock"
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Pacing signal card - plain inline icon + label + zone pill on the left
    /// (matches the metric tile treatment for visual consistency - no badged
    /// circle), glowing delta on the right, clean runway below, always-present
    /// message row so sibling cards keep the same height.
    private func pacingSignal(pacing: PacingResult, label: String, icon: String) -> some View {
        let tint = themeStore.current.pacingColor(for: pacing.zone)
        let sign = pacing.delta >= 0 ? "+" : ""
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 16)
                        Text(label.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .tracking(1.5)
                    }
                    HStack(spacing: 5) {
                        Circle()
                            .fill(tint)
                            .frame(width: 5, height: 5)
                            .shadow(color: tint, radius: 3)
                        Text(zoneLabel(pacing.zone))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint)
                            .tracking(1.2)
                    }
                }

                Spacer()

                GlowText(
                    "\(sign)\(Int(pacing.delta))%",
                    font: .system(size: 34, weight: .heavy, design: .rounded),
                    color: tint,
                    glowRadius: 6
                )
            }

            runwayRuler(actual: pacing.actualUsage, expected: pacing.expectedUsage, tint: tint)

            Text(pacing.message.isEmpty ? " " : pacing.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint.opacity(pacing.message.isEmpty ? 0 : 0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pacingBackground(tint: tint))
    }

    private func zoneLabel(_ zone: PacingZone) -> String {
        switch zone {
        case .chill: return String(localized: "pacing.zone.chill")
        case .onTrack: return String(localized: "pacing.zone.ontrack")
        case .hot: return String(localized: "pacing.zone.hot")
        }
    }

    /// Runway bar with a distinctive "time cursor" for the expected position -
    /// twin white chevrons (▼ above, ▲ below) frame the ideal-pace spot like a
    /// target bracket, clearly separate from the glowing "now" dot that marks
    /// actual usage. The tricolor track hints at chill / on-track / hot zones.
    private func runwayRuler(actual: Double, expected: Double, tint: Color) -> some View {
        let clampedActual = min(max(actual, 0), 100)
        let clampedExpected = min(max(expected, 0), 100)
        let trackH: CGFloat = 6
        let chevronH: CGFloat = 5
        let chevronW: CGFloat = 9
        let gap: CGFloat = 3
        let dotSize: CGFloat = 12
        let trackY: CGFloat = chevronH + gap            // 8
        let trackMid: CGFloat = trackY + trackH / 2      // 11
        let bottomChevronY: CGFloat = trackY + trackH + gap  // 17
        let dotTop: CGFloat = trackMid - dotSize / 2     // 5
        let totalH: CGFloat = bottomChevronY + chevronH  // 22

        return GeometryReader { geo in
            let w = geo.size.width
            let actualX = w * CGFloat(clampedActual) / 100
            let expectedX = w * CGFloat(clampedExpected) / 100

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: trackH / 2)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.40, green: 0.85, blue: 0.55).opacity(0.22),
                            Color(red: 0.95, green: 0.80, blue: 0.30).opacity(0.22),
                            Color(red: 0.95, green: 0.40, blue: 0.35).opacity(0.22),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(height: trackH)
                    .offset(y: trackY)

                RoundedRectangle(cornerRadius: trackH / 2)
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.7), tint],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(0, actualX), height: trackH)
                    .offset(y: trackY)
                    .shadow(color: tint.opacity(0.5), radius: 4)

                // Top chevron pointing down at expected position.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: chevronW, y: 0))
                    p.addLine(to: CGPoint(x: chevronW / 2, y: chevronH))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.95))
                .frame(width: chevronW, height: chevronH)
                .shadow(color: .white.opacity(0.35), radius: 3)
                .offset(x: max(0, expectedX - chevronW / 2), y: 0)

                // Bottom chevron pointing up at expected position.
                Path { p in
                    p.move(to: CGPoint(x: chevronW / 2, y: 0))
                    p.addLine(to: CGPoint(x: chevronW, y: chevronH))
                    p.addLine(to: CGPoint(x: 0, y: chevronH))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.95))
                .frame(width: chevronW, height: chevronH)
                .shadow(color: .white.opacity(0.35), radius: 3)
                .offset(x: max(0, expectedX - chevronW / 2), y: bottomChevronY)

                Circle()
                    .fill(Color.white)
                    .frame(width: dotSize, height: dotSize)
                    .shadow(color: tint.opacity(0.75), radius: 5)
                    .shadow(color: tint.opacity(0.5), radius: 10)
                    .offset(x: max(0, actualX - dotSize / 2), y: dotTop)
            }
        }
        .frame(height: totalH)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: actual)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: expected)
    }

    private func pacingBackground(tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [tint.opacity(0.09), tint.opacity(0.015)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: 16)
                .stroke(tint.opacity(0.22), lineWidth: 0.8)
        }
    }

    // MARK: - Footer Status (tier / org inline pills)

    private var footerStatus: some View {
        HStack(spacing: 8) {
            if let tier = usageStore.rateLimitTier {
                statusPill(
                    icon: "sparkles",
                    label: String(localized: "dashboard.tier"),
                    value: tier.formattedRateLimitTier,
                    tint: Color(red: 0.18, green: 0.82, blue: 0.74)
                )
            }
            if let org = usageStore.organizationName {
                statusPill(
                    icon: "building.2.fill",
                    label: String(localized: "dashboard.org"),
                    value: org,
                    tint: Color(red: 0.70, green: 0.55, blue: 0.95)
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func statusPill(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1.2)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(tint.opacity(0.25), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Extra usage

    private func extraUsageCard(_ extra: ExtraUsage) -> some View {
        let used = extra.usedCredits ?? 0
        let limit = extra.monthlyLimit ?? 0
        let pct = extra.utilization.map { Int($0) } ?? (limit > 0 ? Int(used / limit * 100) : 0)
        let currency = extra.currency ?? "USD"
        let tint = pct >= 85 ? Color(red: 0.95, green: 0.4, blue: 0.4)
                 : pct >= 60 ? Color(red: 0.95, green: 0.65, blue: 0.25)
                             : Color(red: 0.45, green: 0.85, blue: 0.6)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "dashboard.extra.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                GlowText(
                    "\(pct)%",
                    font: .system(size: 18, weight: .bold, design: .rounded),
                    color: tint,
                    glowRadius: 3
                )
            }

            if limit > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [tint.opacity(0.7), tint],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100.0)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(CurrencyFormatter.formatMinorUnits(used, currencyCode: currency))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(String(localized: "dashboard.extra.separator"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(CurrencyFormatter.formatMinorUnits(limit, currencyCode: currency))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(String(localized: "dashboard.extra.monthly"))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            } else {
                Text(String(localized: "dashboard.extra.noLimit"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Theme Helpers

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

    private func gaugeColor(for pct: Int) -> Color {
        themeStore.current.gaugeColor(for: Double(pct), thresholds: themeStore.thresholds)
    }

    private func gaugeGradient(for pct: Int) -> LinearGradient {
        themeStore.current.gaugeGradient(for: Double(pct), thresholds: themeStore.thresholds, startPoint: .leading, endPoint: .trailing)
    }
}

import SwiftUI

/// Stats space -> tile-based dashboard.
///
/// Layout follows the CleanMyMac X language : a prominent hero tile carrying
/// the dominant session metric, a grid of secondary metric tiles, a pacing
/// signal row, and an optional extra-usage card. Every surface uses
/// `dsGlass` and pulls colors from `DS` tokens for chrome, while the
/// gauge/pacing colors continue to flow from `ThemeStore` so user themes
/// (default / neon / pastel / monochrome) stay in control of the data hue.
struct MonitoringView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var lastUpdateText = ""
    @State private var heroHover = false
    @State private var hoveredTileID: String? = nil
    @State private var refreshHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                header
                heroTile
                metricsGrid
                pacingRow
                if let extra = usageStore.extraUsage, extra.isEnabled {
                    extraUsageTile(extra)
                }
                footerPills
            }
            .padding(DS.Spacing.md)
        }
        .task {
            refreshLastUpdateText()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                refreshLastUpdateText()
            }
        }
        .onChange(of: usageStore.lastUpdate) { _, _ in refreshLastUpdateText() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            HStack(spacing: 8) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                Text("TokenEater")
                    .font(DS.Typography.title1)
                    .foregroundStyle(DS.Palette.textPrimary)
            }

            if usageStore.planType != .unknown {
                Text(usageStore.planType.displayLabel)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                            .fill(DS.Palette.brandPrimary.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                                    .stroke(DS.Palette.brandPrimary.opacity(0.5), lineWidth: 0.6)
                            )
                    )
            }

            Spacer()

            if usageStore.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            }

            if !lastUpdateText.isEmpty {
                Text(String(format: String(localized: "menubar.updated"), lastUpdateText))
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            Button {
                Task { await usageStore.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(refreshHovering ? DS.Palette.accentHistory : DS.Palette.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(refreshHovering
                                  ? DS.Palette.accentHistory.opacity(0.18)
                                  : DS.Palette.glassFill)
                            .overlay(
                                Circle().stroke(
                                    refreshHovering
                                        ? DS.Palette.accentHistory.opacity(0.55)
                                        : DS.Palette.glassBorder,
                                    lineWidth: 1
                                )
                            )
                    )
                    .shadow(color: refreshHovering ? DS.Palette.accentHistory.opacity(0.55) : .clear,
                            radius: refreshHovering ? 8 : 0)
                    .scaleEffect(refreshHovering && !reduceMotion ? 1.05 : 1.0)
            }
            .buttonStyle(.plain)
            .help(String(localized: "contextmenu.refresh"))
            .onHover { hovering in
                withAnimation(DS.Motion.springSnap) { refreshHovering = hovering }
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    // MARK: - Hero tile (Session 5H)

    private var heroTile: some View {
        let pct = usageStore.fiveHourPct
        let resetDate = usageStore.lastUsage?.fiveHour?.resetsAtDate
        let gaugeColor = gaugeColor(pct: pct, resetDate: resetDate, windowDuration: 5 * 3600)
        let gaugeGradient = gaugeGradient(pct: pct, resetDate: resetDate, windowDuration: 5 * 3600)
        let zone = usageStore.fiveHourPacing?.zone
        let accent = DS.Palette.accentStats

        return HStack(alignment: .center, spacing: DS.Spacing.lg) {
            // Left -> labels + meta
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xs) {
                    Circle()
                        .fill(gaugeColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: gaugeColor.opacity(0.6), radius: 4)
                    Text(String(localized: "dashboard.hero.session.label").uppercased())
                        .font(DS.Typography.micro)
                        .tracking(1.5)
                        .foregroundStyle(DS.Palette.textSecondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(pct)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(gaugeColor)
                        .shadow(color: gaugeColor.opacity(0.45), radius: 10)
                        .contentTransition(.numericText(value: Double(pct)))
                        .animation(DS.Motion.springLiquid, value: pct)
                    Text("%")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(gaugeColor.opacity(0.55))
                        .baselineOffset(5)
                }

                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                    Text(String(localized: "dashboard.hero.resetsIn").uppercased())
                        .font(DS.Typography.micro)
                        .tracking(1.2)
                        .foregroundStyle(DS.Palette.textTertiary)
                    Text(usageStore.fiveHourReset.isEmpty ? "-" : usageStore.fiveHourReset)
                        .font(DS.Typography.metricInline)
                        .foregroundStyle(DS.Palette.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right -> ring + zone glyph
            ZStack {
                RadialGradient(
                    colors: [gaugeColor.opacity(0.20), gaugeColor.opacity(0.04), .clear],
                    center: .center,
                    startRadius: 10,
                    endRadius: 90
                )
                .frame(width: 200, height: 200)
                .blur(radius: 14)
                .allowsHitTesting(false)

                RingGauge(
                    percentage: pct,
                    gradient: gaugeGradient,
                    size: 140,
                    glowColor: gaugeColor,
                    glowRadius: 8
                )

                Image(systemName: zoneGlyph(for: zone))
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(zone.map { themeStore.current.pacingColor(for: $0) } ?? gaugeColor)
                    .shadow(color: (zone.map { themeStore.current.pacingColor(for: $0) } ?? gaugeColor).opacity(0.55), radius: 10)
                    .animation(DS.Motion.springLiquid, value: zone)
            }
            .frame(width: 160, height: 160)
        }
        .padding(DS.Spacing.lg)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.cardLg)
                    .fill(DS.Palette.bgElevated.opacity(0.85))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: DS.Radius.cardLg)
                    )
                RoundedRectangle(cornerRadius: DS.Radius.cardLg)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.10), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.cardLg)
                .stroke(
                    LinearGradient(
                        colors: [accent.opacity(heroHover ? 0.35 : 0.15), accent.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .dsShadow(heroHover ? DS.Shadow.lift : DS.Shadow.subtle)
        .scaleEffect(heroHover ? 1.004 : 1.0)
        .onHover { hovering in
            withAnimation(DS.Motion.springSnap) { heroHover = hovering }
        }
    }

    // MARK: - Metrics grid

    private var metricsGrid: some View {
        let tiles = secondaryTiles
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3), spacing: DS.Spacing.sm) {
            ForEach(tiles, id: \.id) { tile in
                MetricTile(
                    id: tile.id,
                    label: tile.label,
                    icon: tile.icon,
                    pct: tile.pct,
                    resetText: tile.resetText,
                    resetDate: tile.resetDate,
                    windowDuration: tile.windowDuration,
                    smartEnabled: settingsStore.smartColorEnabled,
                    isHovered: hoveredTileID == tile.id,
                    themeStore: themeStore
                ) { hovering in
                    withAnimation(DS.Motion.springSnap) {
                        hoveredTileID = hovering ? tile.id : (hoveredTileID == tile.id ? nil : hoveredTileID)
                    }
                }
            }
        }
    }

    private var secondaryTiles: [TileDescriptor] {
        let weekWindow: TimeInterval = 7 * 86_400
        var tiles: [TileDescriptor] = [
            TileDescriptor(
                id: "weekly",
                label: String(localized: "metric.weekly"),
                icon: "calendar",
                pct: usageStore.sevenDayPct,
                resetText: usageStore.sevenDayReset,
                resetDate: usageStore.lastUsage?.sevenDay?.resetsAtDate,
                windowDuration: weekWindow
            ),
            TileDescriptor(
                id: "sonnet",
                label: String(localized: "metric.sonnet"),
                icon: "text.quote",
                pct: usageStore.sonnetPct,
                resetText: usageStore.sonnetReset.isEmpty ? nil : usageStore.sonnetReset,
                resetDate: usageStore.lastUsage?.sevenDaySonnet?.resetsAtDate,
                windowDuration: weekWindow
            )
        ]
        if usageStore.hasDesign {
            tiles.append(TileDescriptor(
                id: "design",
                label: String(localized: "metric.design"),
                icon: "paintbrush.pointed.fill",
                pct: usageStore.designPct,
                resetText: usageStore.designReset.isEmpty ? nil : usageStore.designReset,
                resetDate: usageStore.lastUsage?.sevenDayDesign?.resetsAtDate,
                windowDuration: weekWindow
            ))
        }
        if usageStore.hasOpus {
            tiles.append(TileDescriptor(
                id: "opus",
                label: "Opus",
                icon: "brain.head.profile",
                pct: usageStore.opusPct,
                resetText: nil,
                resetDate: nil,
                windowDuration: weekWindow
            ))
        }
        if usageStore.hasCowork {
            tiles.append(TileDescriptor(
                id: "cowork",
                label: "Cowork",
                icon: "person.2.fill",
                pct: usageStore.coworkPct,
                resetText: nil,
                resetDate: nil,
                windowDuration: weekWindow
            ))
        }
        return tiles
    }

    // MARK: - Pacing row

    private var pacingRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let pacing = usageStore.fiveHourPacing {
                pacingCard(pacing: pacing, label: String(localized: "pacing.session.label"), icon: "clock.fill")
                    .frame(maxWidth: .infinity)
            }
            if let pacing = usageStore.pacingResult {
                pacingCard(pacing: pacing, label: String(localized: "pacing.weekly.label"), icon: "calendar.badge.clock")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func pacingCard(pacing: PacingResult, label: String, icon: String) -> some View {
        let tint = themeStore.current.pacingColor(for: pacing.zone)
        let sign = pacing.delta >= 0 ? "+" : ""
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.xs) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                        Text(label.uppercased())
                            .font(DS.Typography.micro)
                            .tracking(1.4)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    HStack(spacing: DS.Spacing.xxs) {
                        Circle()
                            .fill(tint)
                            .frame(width: 5, height: 5)
                            .shadow(color: tint, radius: 3)
                        Text(zoneLabel(pacing.zone))
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(tint)
                    }
                }
                Spacer()
                Text("\(sign)\(Int(pacing.delta))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.45), radius: 5)
                    .contentTransition(.numericText(value: pacing.delta))
                    .animation(DS.Motion.springLiquid, value: pacing.delta)
            }

            pacingTrack(actual: pacing.actualUsage, expected: pacing.expectedUsage, tint: tint)

            if !pacing.message.isEmpty {
                Text(pacing.message)
                    .font(DS.Typography.label)
                    .foregroundStyle(tint.opacity(0.85))
                    .lineLimit(1)
            } else {
                Text(" ")
                    .font(DS.Typography.label)
                    .foregroundStyle(.clear)
                    .lineLimit(1)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(DS.Palette.bgElevated.opacity(0.85))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(LinearGradient(colors: [tint.opacity(0.06), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
        .dsShadow(DS.Shadow.subtle)
    }

    private func pacingTrack(actual: Double, expected: Double, tint: Color) -> some View {
        let clampedActual = min(max(actual, 0), 100)
        let clampedExpected = min(max(expected, 0), 100)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(DS.Palette.glassFillHi)
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(clampedActual) / 100, height: 6)
                    .shadow(color: tint.opacity(0.4), radius: 4)
                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: 12)
                    .offset(x: geo.size.width * CGFloat(clampedExpected) / 100 - 1, y: -3)
                    .shadow(color: .white.opacity(0.4), radius: 2)
            }
        }
        .frame(height: 12)
        .animation(DS.Motion.springLiquid, value: actual)
        .animation(DS.Motion.springLiquid, value: expected)
    }

    // MARK: - Extra usage

    private func extraUsageTile(_ extra: ExtraUsage) -> some View {
        let used = extra.usedCredits ?? 0
        let limit = extra.monthlyLimit ?? 0
        let pct = extra.utilization.map { Int($0) } ?? (limit > 0 ? Int(used / limit * 100) : 0)
        let currency = extra.currency ?? "USD"
        let tint = pct >= 85 ? DS.Palette.semanticError
                 : pct >= 60 ? DS.Palette.semanticWarning
                             : DS.Palette.semanticSuccess

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text(String(localized: "dashboard.extra.title"))
                    .font(DS.Typography.title2)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                Text("\(pct)%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.45), radius: 4)
            }
            if limit > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Palette.glassFillHi)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100)
                    }
                }
                .frame(height: 6)
                HStack(spacing: DS.Spacing.xs) {
                    Text(CurrencyFormatter.formatMinorUnits(used, currencyCode: currency, locale: Locale(identifier: "en_US")))
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Text(String(localized: "dashboard.extra.separator"))
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Palette.textTertiary)
                    Text(CurrencyFormatter.formatMinorUnits(limit, currencyCode: currency, locale: Locale(identifier: "en_US")))
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                    Text(String(localized: "dashboard.extra.monthly"))
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            } else {
                Text(String(localized: "dashboard.extra.noLimit"))
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(radius: DS.Radius.card)
        .dsShadow(DS.Shadow.subtle)
    }

    // MARK: - Footer pills

    private var footerPills: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let tier = usageStore.rateLimitTier {
                statusPill(icon: "sparkles", label: String(localized: "dashboard.tier"), value: tier.formattedRateLimitTier, tint: DS.Palette.accentStats)
            }
            if let org = usageStore.organizationName {
                statusPill(icon: "building.2.fill", label: String(localized: "dashboard.org"), value: org, tint: DS.Palette.accentHistory)
            }
            Spacer()
        }
    }

    private func statusPill(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(DS.Typography.micro)
                .tracking(1.2)
                .foregroundStyle(DS.Palette.textTertiary)
            Text(value)
                .font(DS.Typography.label)
                .fontWeight(.semibold)
                .foregroundStyle(DS.Palette.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                .fill(DS.Palette.glassFill)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Helpers

    /// Smart-aware gauge color helper. When the user enabled "Smart Color" in
    /// Themes, uses the risk-aware formula (utilization x time-to-reset);
    /// otherwise falls back to the static threshold ramp.
    private func gaugeColor(pct: Int, resetDate: Date?, windowDuration: TimeInterval) -> Color {
        if settingsStore.smartColorEnabled {
            return themeStore.current.smartGaugeColor(
                utilization: Double(pct),
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: themeStore.thresholds
            )
        }
        return themeStore.current.gaugeColor(for: Double(pct), thresholds: themeStore.thresholds)
    }

    private func gaugeGradient(pct: Int, resetDate: Date?, windowDuration: TimeInterval) -> LinearGradient {
        if settingsStore.smartColorEnabled {
            return themeStore.current.smartGaugeGradient(
                utilization: Double(pct),
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: themeStore.thresholds,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return themeStore.current.gaugeGradient(
            for: Double(pct),
            thresholds: themeStore.thresholds,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func zoneGlyph(for zone: PacingZone?) -> String {
        switch zone {
        case .chill:   "leaf.fill"
        case .onTrack: "bolt.fill"
        case .warning: "hare.fill"
        case .hot:     "flame.fill"
        case nil:      "sparkles"
        }
    }

    private func zoneLabel(_ zone: PacingZone) -> String {
        switch zone {
        case .chill:   String(localized: "pacing.zone.chill")
        case .onTrack: String(localized: "pacing.zone.ontrack")
        case .warning: String(localized: "pacing.zone.warning")
        case .hot:     String(localized: "pacing.zone.hot")
        }
    }

    private func refreshLastUpdateText() {
        if let date = usageStore.lastUpdate {
            lastUpdateText = date.formatted(.relative(presentation: .named))
        }
    }
}

// MARK: - Tile descriptor + MetricTile

private struct TileDescriptor {
    let id: String
    let label: String
    let icon: String
    let pct: Int
    let resetText: String?
    let resetDate: Date?
    let windowDuration: TimeInterval
}

private struct MetricTile: View {
    let id: String
    let label: String
    let icon: String
    let pct: Int
    let resetText: String?
    let resetDate: Date?
    let windowDuration: TimeInterval
    let smartEnabled: Bool
    let isHovered: Bool
    let themeStore: ThemeStore
    let onHoverChange: (Bool) -> Void

    var body: some View {
        let color: Color = smartEnabled
            ? themeStore.current.smartGaugeColor(
                utilization: Double(pct),
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: themeStore.thresholds
            )
            : themeStore.current.gaugeColor(for: Double(pct), thresholds: themeStore.thresholds)
        let clamped = CGFloat(min(max(pct, 0), 100)) / 100
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color.opacity(0.8))
                    .frame(width: 14)
                Text(label.uppercased())
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(pct)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(pct)))
                    .animation(DS.Motion.springLiquid, value: pct)
                Text("%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(color.opacity(0.55))
                    .baselineOffset(3)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.Palette.glassFillHi)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * clamped, height: 3)
                        .shadow(color: color.opacity(0.5), radius: 3)
                }
            }
            .frame(height: 3)
            .animation(DS.Motion.springLiquid, value: pct)

            Group {
                if let resetText, !resetText.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(String(localized: "dashboard.hero.resetsIn").uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(resetText)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                } else {
                    Text(" ")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.clear)
                }
            }
            .lineLimit(1)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                // L2 inner panel - sits visibly on top of L1 hero / containers
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(DS.Palette.bgPanel.opacity(0.92))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card))
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(LinearGradient(colors: [color.opacity(isHovered ? 0.10 : 0.05), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .stroke(color.opacity(isHovered ? 0.40 : 0.18), lineWidth: 1)
        )
        .dsShadow(isHovered ? DS.Shadow.lift : DS.Shadow.subtle)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .offset(y: isHovered ? -1 : 0)
        .onHover(perform: onHoverChange)
    }
}

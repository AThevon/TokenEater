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
    @EnvironmentObject private var sessionStore: SessionStore

    /// Lightweight 7d daily-buckets store dedicated to the back-of-card
    /// stats. Loaded once on appear, refreshed if older than 60s.
    /// Independent from HistoryView's HistoryStore (different lifecycle).
    @StateObject private var insightsStore = MonitoringInsightsStore()

    @State private var lastUpdateText = ""
    @State private var heroHover = false
    @State private var refreshHovering = false
    // Hero flip state - lives at the parent because heroTile is a
    // computed var (not its own struct). Reset automatically when the
    // user navigates away from Monitoring (MainAppView .id(selectedSpace)
    // recreates MonitoringView, clearing all @State).
    @State private var heroFlipped: Bool = false
    @State private var heroBlurProgress: CGFloat = 0
    @State private var heroFlipping: Bool = false
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
        .onAppear { insightsStore.warmIfStale() }
        .onChange(of: usageStore.lastUpdate) { _, _ in refreshLastUpdateText() }
    }

    /// Maps a tile id to the matching `ModelFamily` (nil = all-models).
    /// `design` / `cowork` map to nil because they're not present in
    /// the JSONL stream that `SessionHistoryService` aggregates - they
    /// fall back to the minimal back-of-card content.
    private func tileFamily(for id: String) -> ModelFamily? {
        switch id {
        case "sonnet": return .sonnet
        case "opus":   return .opus
        case "weekly": return nil
        default:       return nil
        }
    }

    /// True only for tiles whose family is represented in the JSONL data
    /// (weekly, sonnet, opus). Design / Cowork get the simple back.
    private func hasRichBack(tileId: String) -> Bool {
        ["weekly", "sonnet", "opus"].contains(tileId)
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
        let pacing = usageStore.fiveHourPacing
        // The card's ambient tint follows the gauge color so the wash, the
        // big number, and the ring all read as a single signal. Using the
        // module accent here used to produce a green-orange-blue mix when
        // the user was in warning territory.
        let accent = gaugeColor

        return Button {
            triggerHeroFlip()
        } label: {
            ZStack {
                if heroFlipped {
                    heroBackContent(
                        gaugeColor: gaugeColor,
                        zone: zone,
                        pacing: pacing,
                        resetDate: resetDate
                    )
                } else {
                    heroFrontContent(
                        pct: pct,
                        gaugeColor: gaugeColor,
                        gaugeGradient: gaugeGradient,
                        zone: zone
                    )
                }
            }
            // Force snap swap (no implicit animation) so the new face
            // is in place at the blur peak, not crossfading during the
            // blur-out. Same fix as MetricTile.
            .animation(nil, value: heroFlipped)
            .padding(DS.Spacing.lg)
            .frame(height: 200)
            .blur(radius: heroBlurProgress * 14.0)
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
                                colors: [accent.opacity(heroHover ? 0.10 : 0.05), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.cardLg)
                    .stroke(accent.opacity(heroHover ? 0.40 : 0.18), lineWidth: 1)
            )
            .dsShadow(heroHover ? DS.Shadow.lift : DS.Shadow.subtle)
        }
        .buttonStyle(CardPressStyle(isHovered: heroHover, accent: accent, cornerRadius: DS.Radius.cardLg))
        .onHover { hovering in
            withAnimation(DS.Motion.springSnap) { heroHover = hovering }
        }
    }

    @ViewBuilder
    private func heroFrontContent(pct: Int, gaugeColor: Color, gaugeGradient: LinearGradient, zone: PacingZone?) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.lg) {
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
                    if let resetDate = usageStore.lastUsage?.fiveHour?.resetsAtDate {
                        Text("·")
                            .font(DS.Typography.metricInline)
                            .foregroundStyle(DS.Palette.textTertiary.opacity(0.5))
                        Text(resetDate.formatted(.dateTime.hour().minute()))
                            .font(DS.Typography.metricInline)
                            .foregroundStyle(DS.Palette.textPrimary)
                    }
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
    }

    /// Hero back face. Left side = pacing graph (equilibrium diagonal +
    /// trajectory + delta fill zone); right side = live session activity.
    /// Reset date stays on the front - no duplication.
    @ViewBuilder
    private func heroBackContent(
        gaugeColor: Color,
        zone: PacingZone?,
        pacing: PacingResult?,
        resetDate: Date?
    ) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xs) {
                    Circle()
                        .fill(gaugeColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: gaugeColor.opacity(0.6), radius: 4)
                    Text(String(localized: "dashboard.hero.session.label").uppercased() + " · PACING")
                        .font(DS.Typography.micro)
                        .tracking(1.5)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Spacer(minLength: 0)
                    if let pacing {
                        Text(String(format: "%+.1f%%", pacing.delta))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(pacing.delta > 0 ? DS.Palette.semanticWarning : DS.Palette.brandPrimary)
                            .monospacedDigit()
                    }
                }

                if let pacing {
                    HeroPacingGraph(
                        actualUsage: pacing.actualUsage,
                        expectedUsage: pacing.expectedUsage,
                        deltaColor: pacing.delta > 0 ? DS.Palette.semanticWarning : DS.Palette.brandPrimary,
                        trajectoryColor: gaugeColor
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
                } else {
                    Spacer(minLength: 0)
                    Text("Pacing data unavailable")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.textTertiary)
                    Spacer(minLength: 0)
                }

                if let zone {
                    HStack(spacing: 6) {
                        Image(systemName: zoneGlyph(for: zone))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(themeStore.current.pacingColor(for: zone))
                        Text(zoneLabel(zone).uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(themeStore.current.pacingColor(for: zone))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right column: live session activity. Sessions count is the
            // headline number; top model fills the line below. Pulls
            // from SessionStore (kept in sync by the overlay watcher).
            VStack(alignment: .trailing, spacing: 6) {
                Text("LIVE")
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.textTertiary)

                let count = sessionStore.activeSessions.count
                Text("\(count)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(count > 0 ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(DS.Motion.springLiquid, value: count)
                Text(count == 1 ? "active session" : "active sessions")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .textCase(.uppercase)

                if let topModel = topActiveModel() {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(gaugeColor)
                            .frame(width: 5, height: 5)
                        Text(topModel)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(width: 160, height: 160)
        }
    }

    /// Most-used model among the currently active Claude Code sessions.
    /// Returns nil when no sessions are tracked or none reported a model.
    private func topActiveModel() -> String? {
        let raws = sessionStore.activeSessions.compactMap { $0.model }
        guard !raws.isEmpty else { return nil }
        let counts = Dictionary(grouping: raws.map { ModelKind(rawModel: $0) }, by: { $0 })
            .mapValues { $0.count }
        return counts.max { $0.value < $1.value }?.key.displayName
    }

    private func statValue(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(1)
                .foregroundStyle(DS.Palette.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    private func triggerHeroFlip() {
        guard !heroFlipping else { return }
        heroFlipping = true
        withAnimation(.easeIn(duration: 0.16)) { heroBlurProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            heroFlipped.toggle()
            withAnimation(.easeOut(duration: 0.24)) { heroBlurProgress = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                heroFlipping = false
            }
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
                    pacingMargin: Double(settingsStore.pacingMargin),
                    themeStore: themeStore,
                    insights: hasRichBack(tileId: tile.id)
                        ? insightsStore.snapshot(for: tileFamily(for: tile.id))
                        : nil,
                    insightsLoaded: insightsStore.hasLoaded
                )
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
                thresholds: themeStore.thresholds,
                pacingMargin: Double(settingsStore.pacingMargin)
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
                pacingMargin: Double(settingsStore.pacingMargin),
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
    let pacingMargin: Double
    let themeStore: ThemeStore
    /// 7d insights snapshot when the tile family has data. Nil for
    /// design / cowork tiles where the JSONL feed has nothing relevant.
    let insights: TileInsightsSnapshot?
    /// True once the insights store has done its first load. Lets the
    /// back face show a "loading..." placeholder vs a "no data" one.
    let insightsLoaded: Bool

    @State private var isHovered: Bool = false
    @State private var showBack: Bool = false
    @State private var blurProgress: CGFloat = 0
    @State private var isFlipping: Bool = false

    var body: some View {
        let color: Color = smartEnabled
            ? themeStore.current.smartGaugeColor(
                utilization: Double(pct),
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: themeStore.thresholds,
                pacingMargin: pacingMargin
            )
            : themeStore.current.gaugeColor(for: Double(pct), thresholds: themeStore.thresholds)
        let clamped = CGFloat(min(max(pct, 0), 100)) / 100

        return Button {
            triggerFlip()
        } label: {
            ZStack {
                if showBack {
                    backContent(color: color)
                } else {
                    frontContent(color: color, clamped: clamped)
                }
            }
            // Critical: disable SwiftUI's implicit animation on the
            // showBack swap. Without this, the surrounding withAnimation
            // (driving the blur) wraps the if/else replacement and
            // implicitly fades / morphs the swap, so the new content
            // crossfades in DURING the blur-out instead of being already
            // there at the blur peak. Result was "blur in blur out PUIS
            // snap" - the swap was lagging behind the visual peak.
            .animation(nil, value: showBack)
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 124)
            .blur(radius: blurProgress * 14.0)
            .background(
                ZStack {
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
        }
        .buttonStyle(CardPressStyle(isHovered: isHovered, accent: color, cornerRadius: DS.Radius.card))
        .onHover { hovering in
            withAnimation(DS.Motion.springSnap) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private func frontContent(color: Color, clamped: CGFloat) -> some View {
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
                        if let resetDate {
                            Text("·")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DS.Palette.textTertiary.opacity(0.5))
                            Text(absoluteResetText(date: resetDate))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(DS.Palette.textSecondary)
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
    }

    /// "16:32" for sub-day windows (5h), "Tue 16:32" for multi-day
    /// windows (7d weeklies). Stays compact + monospaced so it sits
    /// discretely next to the countdown without competing for space.
    private func absoluteResetText(date: Date) -> String {
        if windowDuration <= 24 * 3600 {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// Back face - "details" view. When `insights` is available (weekly,
    /// sonnet, opus tiles) we show a rich 7d breakdown; otherwise we
    /// fall back to a minimal placeholder. Card dimensions match the
    /// front via the parent's fixed height.
    @ViewBuilder
    private func backContent(color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header line: same icon + label structure as the front so
            // the card identity stays anchored across the swap.
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color.opacity(0.8))
                    .frame(width: 14)
                Text("\(label.uppercased()) · 7D")
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let delta = insights?.deltaPercent {
                    Text(String(format: "%+.0f%%", delta))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(delta >= 0 ? DS.Palette.semanticWarning : DS.Palette.brandPrimary)
                        .monospacedDigit()
                }
            }

            if let snapshot = insights {
                richBackBody(snapshot: snapshot, color: color)
            } else if !insightsLoaded {
                Spacer(minLength: 0)
                Text("Loading...")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            } else {
                fallbackBackBody(color: color)
            }
        }
    }

    @ViewBuilder
    private func richBackBody(snapshot: TileInsightsSnapshot, color: Color) -> some View {
        // Mini sparkline of the 7 daily totals.
        sparklineBars(snapshot.sparkline, color: color)

        Spacer(minLength: 0)

        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("TOTAL")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(DS.Palette.textTertiary)
                Text(formatTokens(snapshot.total))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            if let heaviest = snapshot.heaviestDay {
                VStack(alignment: .leading, spacing: 1) {
                    Text("PEAK")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(DS.Palette.textTertiary)
                    HStack(spacing: 4) {
                        Text(heaviest.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Palette.textPrimary)
                        Text(formatTokens(heaviest.tokens))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Fallback when no JSONL family data exists for this tile (design /
    /// cowork). Keeps the card useful by surfacing the full reset date
    /// instead of leaving the back empty.
    @ViewBuilder
    private func fallbackBackBody(color: Color) -> some View {
        Spacer(minLength: 0)
        if let resetDate {
            VStack(alignment: .leading, spacing: 2) {
                Text("RESETS")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(DS.Palette.textTertiary)
                Text(resetDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        Text("\(windowText) rolling")
            .font(.system(size: 9))
            .foregroundStyle(DS.Palette.textTertiary)
    }

    /// 7-bar mini chart showing daily totals. Bars share their height
    /// scale with the maximum value in the series so the relative
    /// distribution reads correctly even when totals are tiny.
    private func sparklineBars(_ values: [Int], color: Color) -> some View {
        let maxValue = max(values.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                let h = CGFloat(value) / CGFloat(maxValue)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(LinearGradient(
                        colors: [color, color.opacity(0.4)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, 32 * h))
                    .opacity(value > 0 ? 1 : 0.18)
            }
        }
        .frame(height: 32)
        .padding(.top, 2)
    }

    /// SI formatter for the back numbers. Mirrors the History view's
    /// formatTokens for consistency.
    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            let m = Double(value) / 1_000_000
            return String(format: m >= 10 ? "%.0fM" : "%.1fM", m)
        }
        if value >= 1_000 {
            let k = Double(value) / 1_000
            return String(format: k >= 10 ? "%.0fk" : "%.1fk", k)
        }
        return "\(value)"
    }

    private var windowText: String {
        let hours = Int(windowDuration / 3600)
        if hours <= 24 { return "\(hours)h rolling" }
        let days = Int(windowDuration / 86_400)
        return "\(days)d rolling"
    }

    private func triggerFlip() {
        guard !isFlipping else { return }
        isFlipping = true
        withAnimation(.easeIn(duration: 0.16)) { blurProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            // Snap swap (no animation) so the back content appears
            // INSTANTLY at the blur peak. Any animation here would
            // visibly fade the new content while the blur is still
            // dropping, producing the "weird blink" we're avoiding.
            showBack.toggle()
            withAnimation(.easeOut(duration: 0.24)) { blurProgress = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                isFlipping = false
            }
        }
    }
}

// MARK: - Card press style

/// Shared press style for clickable cards (MetricTile + hero). On hover
/// the card lifts +1px and scales 1.01. On press it dips to 0.996 with
/// a subtle accent border flash for tactile feedback. No Y offset on
/// press (the user wanted "extra fin" - just a hint of depth dip).
private struct CardPressStyle: ButtonStyle {
    let isHovered: Bool
    let accent: Color
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let scale: CGFloat = pressed ? 0.996 : (isHovered ? 1.01 : 1.0)
        let lift: CGFloat = isHovered ? -1 : 0

        return configuration.label
            .scaleEffect(scale)
            .offset(y: lift)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accent.opacity(pressed ? 0.45 : 0), lineWidth: 1)
            )
            // Snap-fast press (no overshoot) so the dip + bounce-back
            // is over before the flip animation even starts. Avoids
            // overlapping bounce springs that read as a blink.
            .animation(.spring(response: 0.10, dampingFraction: 0.95), value: pressed)
            .animation(.spring(response: 0.30, dampingFraction: 0.85), value: isHovered)
    }
}

// MARK: - Hero pacing graph

/// Compact pacing visualisation for the hero card back. Plots
/// - the equilibrium diagonal (linear pacing from 0% to 100% over the
///   window, dashed, neutral colour),
/// - the user's actual trajectory line from origin to the current point
///   `(expectedUsage, actualUsage)` on the chart,
/// - a filled area showing the delta between the trajectory and the
///   equilibrium line, coloured by whether the user is ahead (warning)
///   or on/under pace (success).
///
/// Both axes are 0...100. `expectedUsage` doubles as "elapsed % of the
/// window" because linear pacing equates the two. So the trajectory
/// always reaches the same X-coordinate as where the equilibrium line
/// sits at that moment - the gap between them is the delta we visualise.
private struct HeroPacingGraph: View {
    let actualUsage: Double
    let expectedUsage: Double
    let deltaColor: Color
    let trajectoryColor: Color

    var body: some View {
        GeometryReader { geo in
            let pad: CGFloat = 6
            let w = geo.size.width
            let h = geo.size.height
            let plotW = max(w - 2 * pad, 1)
            let plotH = max(h - 2 * pad, 1)

            let actualClamped = min(max(actualUsage, 0), 100)
            let expectedClamped = min(max(expectedUsage, 0), 100)

            let originPoint = CGPoint(x: pad, y: h - pad)
            let endDiagonal = CGPoint(x: pad + plotW, y: pad)
            let actualPoint = CGPoint(
                x: pad + plotW * expectedClamped / 100,
                y: h - pad - plotH * actualClamped / 100
            )
            let equilibriumAtX = CGPoint(
                x: actualPoint.x,
                y: h - pad - plotH * expectedClamped / 100
            )

            ZStack {
                // Subtle grid bg - 25/50/75% horizontal ticks for scale.
                Path { path in
                    for fraction in [0.25, 0.5, 0.75] {
                        let y = h - pad - plotH * fraction
                        path.move(to: CGPoint(x: pad, y: y))
                        path.addLine(to: CGPoint(x: pad + plotW, y: y))
                    }
                }
                .stroke(DS.Palette.glassBorderLo, style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))

                // Equilibrium diagonal (linear pacing reference).
                Path { path in
                    path.move(to: originPoint)
                    path.addLine(to: endDiagonal)
                }
                .stroke(DS.Palette.textTertiary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // Filled delta zone between the trajectory and equilibrium
                // at the current X coordinate. Triangle from origin to
                // both points so the fill grows / shrinks with the delta.
                Path { path in
                    path.move(to: originPoint)
                    path.addLine(to: actualPoint)
                    path.addLine(to: equilibriumAtX)
                    path.closeSubpath()
                }
                .fill(deltaColor.opacity(0.22))

                // Trajectory line - solid in the gauge colour.
                Path { path in
                    path.move(to: originPoint)
                    path.addLine(to: actualPoint)
                }
                .stroke(trajectoryColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Current point marker.
                Circle()
                    .fill(trajectoryColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: trajectoryColor.opacity(0.6), radius: 5)
                    .position(actualPoint)
            }
        }
    }
}

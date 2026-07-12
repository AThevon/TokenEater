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
    @EnvironmentObject private var vendorStatusStore: VendorStatusStore

    /// Lightweight 7d daily-buckets store for the back-of-card stats.
    /// Loaded once on appear, refreshed if older than 60s. Owned by
    /// `MainAppView` so the cache survives navigation between spaces.
    @ObservedObject var insightsStore: MonitoringInsightsStore

    @State private var lastUpdateText = ""
    @State private var heroHover = false
    @State private var refreshHovering = false
    // Hero flip state lives at the parent because `heroTile` is a
    // computed var (not its own struct).
    @State private var heroFlipped: Bool = false
    @State private var heroBlurProgress: CGFloat = 0
    @State private var heroFlipping: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.glowIntensity) private var glowIntensity

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                header
                if vendorStatusStore.isDegraded, let status = vendorStatusStore.claudeStatus {
                    outageCard(status)
                }
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
        // Ambient tint follows the gauge color so the wash, the big
        // number, and the ring all read as a single signal.
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
            // Snap swap (no implicit animation) so the new face is in
            // place at the blur peak rather than crossfading.
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
                        .dsGlow(gaugeColor, radius: 4, opacity: 0.6)
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
                        .dsGlow(gaugeColor, radius: 10, opacity: 0.45)
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
                if glowIntensity == .glow {
                    RadialGradient(
                        colors: [gaugeColor.opacity(0.20), gaugeColor.opacity(0.04), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 90
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 14)
                    .allowsHitTesting(false)
                }

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
                    .dsGlow(zone.map { themeStore.current.pacingColor(for: $0) } ?? gaugeColor, radius: 10, opacity: 0.55)
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
                        .dsGlow(gaugeColor, radius: 4, opacity: 0.6)
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

                if let topModel = sessionStore.topActiveModelName {
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
        // Width-filling rows instead of a fixed 3-column grid: the number of
        // secondary tiles varies (Design/Opus/Cowork are shown only when their
        // API bucket exists), so a fixed grid left an empty trailing cell when
        // the count was not a multiple of 3. Each row's tiles stretch to fill
        // the full width, so there is never a hole regardless of tile count.
        let rows = MetricsGridLayout.rows(secondaryTiles)
        return VStack(spacing: DS.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(row, id: \.id) { tile in
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
                            smartProfile: settingsStore.smartColorProfile,
                            themeStore: themeStore,
                            insights: hasRichBack(tileId: tile.id)
                                ? insightsStore.snapshot(for: tileFamily(for: tile.id))
                                : nil,
                            insightsLoaded: insightsStore.hasLoaded
                        )
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
        if usageStore.hasFable {
            tiles.append(TileDescriptor(
                id: "fable",
                label: String(localized: "metric.fable"),
                icon: "books.vertical.fill",
                pct: usageStore.fablePct,
                resetText: usageStore.fableReset.isEmpty ? nil : usageStore.fableReset,
                resetDate: usageStore.lastUsage?.sevenDayFable?.resetsAtDate,
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
                pacingCard(pacing: pacing, label: String(localized: "pacing.weekly.label"), icon: "calendar.badge.clock", showWorkweekBadge: true)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func pacingCard(pacing: PacingResult, label: String, icon: String, showWorkweekBadge: Bool = false) -> some View {
        let tint = themeStore.current.pacingColor(for: pacing.zone)
        let sign = pacing.delta >= 0 ? "+" : ""
        let schedule = settingsStore.pacingSchedule
        let offRanges: [ClosedRange<Double>] = (showWorkweekBadge && schedule.isActive)
            ? (pacing.resetDate.map { schedule.offDayRanges(resetDate: $0) } ?? [])
            : []
        let nowInOffDay = showWorkweekBadge && schedule.isOffDay(Date())
        // Calendar-time position for the "now" marker so it aligns with the
        // off-day hatch (#194). nil keeps the active-time expected position.
        let markerFraction: Double? = (showWorkweekBadge && schedule.isActive)
            ? pacing.resetDate.map { schedule.nowFraction(resetDate: $0) }
            : nil
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
                        if showWorkweekBadge {
                            WorkweekBadge(schedule: settingsStore.pacingSchedule, tint: DS.Palette.textTertiary)
                        }
                    }
                    HStack(spacing: DS.Spacing.xxs) {
                        Circle()
                            .fill(tint)
                            .frame(width: 5, height: 5)
                            .dsGlow(tint, radius: 3, opacity: 1.0)
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
                    .dsGlow(tint, radius: 5, opacity: 0.45)
                    .contentTransition(.numericText(value: pacing.delta))
                    .animation(DS.Motion.springLiquid, value: pacing.delta)
            }

            pacingTrack(actual: pacing.actualUsage, expected: pacing.expectedUsage, tint: tint, offDayRanges: offRanges, nowInOffDay: nowInOffDay, markerFraction: markerFraction)

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

    private func pacingTrack(actual: Double, expected: Double, tint: Color, offDayRanges: [ClosedRange<Double>] = [], nowInOffDay: Bool = false, markerFraction: Double? = nil) -> some View {
        let clampedActual = min(max(actual, 0), 100)
        let clampedExpected = min(max(expected, 0), 100)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(DS.Palette.glassFillHi)
                    .frame(height: 6)
                if !offDayRanges.isEmpty {
                    OffDayHatch(ranges: offDayRanges, cornerRadius: 3)
                        .frame(height: 6)
                }
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(clampedActual) / 100, height: 6)
                    .dsGlow(tint, radius: 4, opacity: 0.4)
                Rectangle()
                    .fill(Color.white.opacity(nowInOffDay ? 0.4 : 0.85))
                    .frame(width: 2, height: 12)
                    .offset(x: (markerFraction.map { geo.size.width * CGFloat(min(max($0, 0), 1)) } ?? (geo.size.width * CGFloat(clampedExpected) / 100)) - 1, y: -3)
                    .dsGlow(.white, radius: 2, opacity: nowInOffDay ? 0.15 : 0.4)
            }
        }
        .frame(height: 12)
        .animation(DS.Motion.springLiquid, value: actual)
        .animation(DS.Motion.springLiquid, value: expected)
    }

    // MARK: - Service status

    private func outageCard(_ status: VendorStatus) -> some View {
        let tint = status.health == .down ? DS.Palette.semanticError : DS.Palette.semanticWarning
        let title = status.health == .down
            ? String(localized: "dashboard.status.down")
            : String(localized: "dashboard.status.degraded")
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                    .dsGlow(tint, radius: 4, opacity: 0.45)
                Text(title)
                    .font(DS.Typography.title2)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer()
                Link(String(localized: "status.banner.view"), destination: status.statusPageURL)
                    .font(DS.Typography.label)
                    .foregroundStyle(tint)
            }
            if let incident = status.activeIncidents.first {
                Text(incident.name)
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !status.affectedComponents.isEmpty {
                Text(String(format: String(localized: "dashboard.status.affected"),
                            status.affectedComponents.joined(separator: ", ")))
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(radius: DS.Radius.card)
        .dsShadow(DS.Shadow.subtle)
    }

    // MARK: - Extra usage

    private func extraUsageTile(_ extra: ExtraUsage) -> some View {
        let used = extra.usedCredits ?? 0
        let limit = extra.monthlyLimit ?? 0
        let pct = extra.utilization.map { Int($0) } ?? (limit > 0 ? Int(used / limit * 100) : 0)
        let currency = extra.currency ?? "USD"
        // Same threshold ladder + theme palette as the menu bar / popover /
        // widgets. Extra Credits has no reset window, so it never uses Smart
        // Color; the static gauge thresholds keep every surface in agreement.
        let tint = themeStore.current.gaugeColor(for: Double(pct), thresholds: themeStore.thresholds)

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
                    .dsGlow(tint, radius: 4, opacity: 0.45)
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
        GaugeColorResolver.color(
            mode: GaugeColorResolver.mode(smartColorEnabled: settingsStore.smartColorEnabled, windowDuration: windowDuration),
            utilization: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            theme: themeStore.current,
            thresholds: themeStore.thresholds,
            pacingMargin: Double(settingsStore.pacingMargin),
            profile: settingsStore.smartColorProfile
        )
    }

    private func gaugeGradient(pct: Int, resetDate: Date?, windowDuration: TimeInterval) -> LinearGradient {
        GaugeColorResolver.gradient(
            mode: GaugeColorResolver.mode(smartColorEnabled: settingsStore.smartColorEnabled, windowDuration: windowDuration),
            utilization: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            theme: themeStore.current,
            thresholds: themeStore.thresholds,
            pacingMargin: Double(settingsStore.pacingMargin),
            profile: settingsStore.smartColorProfile,
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



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
    @EnvironmentObject private var codexStore: CodexUsageStore
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

                // One ordered list drives all three modes. A provider mode
                // renders it once; All renders it once per provider, side by
                // side, which is what makes the columns line up row for row
                // without anything coordinating them. The order and the
                // visibility come from Studio.
                if isComparing {
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        ForEach(visibleProviders) { provider in
                            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                ProviderStatusNotice(provider: provider)
                                blocks(for: provider)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.glanceCard)
                        }
                    }
                } else if let provider = visibleProviders.first {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        ProviderStatusNotice(provider: provider)
                        blocks(for: provider)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.glanceCard)
                }
                CodexInvitationRow()
            }
            // The whole block changes shape on a mode switch, not just the
            // band it used to live on, so the animation moved up with it. One
            // value drives it, and `glide` has no overshoot because these
            // cards are expensive to rasterise at a new size.
            .animation(reduceMotion ? nil : DS.Motion.glide, value: visibleProviders)
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
    /// `cowork` maps to nil because it's not present in the JSONL stream
    /// that `SessionHistoryService` aggregates - it falls back to the
    /// minimal back-of-card content.
    private func tileFamily(for id: String) -> ModelFamily? {
        switch id {
        case "sonnet": return .sonnet
        case "opus":   return .opus
        case "weekly": return nil
        default:       return nil
        }
    }

    /// True only for tiles whose family is represented in the JSONL data
    /// (weekly, sonnet, opus). Cowork gets the simple back.
    private func hasRichBack(tileId: String) -> Bool {
        ["weekly", "sonnet", "opus"].contains(tileId)
    }

    // MARK: - Glance window

    /// Which Claude window the glance card shows. Automatic means the shortest
    /// window the provider actually has, which for Claude is always the
    /// 5-hour one: that is the window that blocks you in the next ten minutes,
    /// while the weekly one is a slower worry. The same rule drives the Codex
    /// card, which is what stops the two cards from quietly answering
    /// different questions.
    enum ClaudeHeroWindow: String, CaseIterable {
        case session
        case weekly

        /// Literal keys rather than an interpolated one: a dynamic key is not
        /// a `LocalizationValue`, and it also hides the string from every tool
        /// that extracts them.
        var localizedLabel: String {
            switch self {
            case .session: return String(localized: "dashboard.hero.window.session")
            case .weekly:  return String(localized: "dashboard.hero.window.weekly")
            }
        }
        var duration: TimeInterval { self == .session ? 5 * 3600 : 7 * 86_400 }
    }

    var claudeHeroWindow: ClaudeHeroWindow {
        settingsStore.heroWindow(for: .claude).flatMap(ClaudeHeroWindow.init(rawValue:)) ?? .session
    }

    /// The window picker lives in a context menu rather than on the card.
    /// The card is a Button that flips on click, and a menu nested in a
    /// Button's label does not reliably receive its own clicks; right-click is
    /// the macOS gesture for "what else can this do" anyway.
    @ViewBuilder
    private func heroWindowMenu(for provider: MetricProvider, options: [(id: String, label: String)]) -> some View {
        Section(String(localized: "dashboard.hero.window.menu")) {
            Button {
                settingsStore.setHeroWindow(nil, for: provider)
            } label: {
                Label(String(localized: "dashboard.hero.window.auto"),
                      systemImage: settingsStore.heroWindow(for: provider) == nil ? "checkmark" : "")
            }
            ForEach(options, id: \.id) { option in
                Button {
                    settingsStore.setHeroWindow(option.id, for: provider)
                } label: {
                    Label(option.label,
                          systemImage: settingsStore.heroWindow(for: provider) == option.id ? "checkmark" : "")
                }
            }
        }
    }

    // MARK: - Glance band

    /// The providers this page is rendering right now, in declaration order.
    /// Everything that used to ask "Claude and/or Codex?" asks this instead,
    /// so adding a third provider changes `activeProviders` and nothing here.
    var visibleProviders: [MetricProvider] {
        settingsStore.activeProviders.filter { settingsStore.activeProviderMode.shows($0) }
    }

    var showsClaude: Bool { visibleProviders.contains(.claude) }

    var showsCodex: Bool { visibleProviders.contains(.codex) }

    /// True when the page has two providers to put side by side. A provider
    /// mode, or a single active provider, gets that provider's own full page
    /// instead: there is nothing to compare, and half a comparison is worse
    /// than none.
    private var isComparing: Bool {
        settingsStore.activeProviderMode == .all && visibleProviders.count > 1
    }

    /// Renders one provider's blocks, in the order Studio put them.
    @ViewBuilder
    private func blocks(for provider: MetricProvider) -> some View {
        ForEach(settingsStore.dashboardComposition.visibleBlocks) { block in
            if block.providers.contains(provider) {
                blockContent(block, for: provider)
            }
        }
    }

    @ViewBuilder
    private func blockContent(_ block: DashboardBlock, for provider: MetricProvider) -> some View {
        switch (block, provider) {
        case (.hero, .claude):
            heroTile
                .contextMenu {
                    heroWindowMenu(for: .claude, options: ClaudeHeroWindow.allCases.map {
                        (id: $0.rawValue, label: $0.localizedLabel)
                    })
                }
        case (.hero, .codex):
            CodexHeroCard()
                .contextMenu {
                    heroWindowMenu(for: .codex, options: codexStore.windows
                        .sorted { $0.windowDuration < $1.windowDuration }
                        .map { (id: $0.kind.rawValue, label: $0.kind.heroLabel(for: $0.windowDuration)) })
                }

        case (.windows, .claude):
            // The hero already shows one window, so the grid never repeats it.
            // In every mode: the duplicate showed up as soon as the hero was
            // pinned to Weekly, which a Claude-only user can do just as well.
            grid(of: secondaryTiles
                .filter { $0.id != claudeHeroTileID }
                .map { labelled($0, for: .claude) })
        case (.windows, .codex):
            grid(of: codexStore.windows
                .sorted { $0.windowDuration < $1.windowDuration }
                .filter { $0.id != codexHeroWindow?.id }
                .map { window in
                    labelled(TileDescriptor(
                        id: "codex-" + window.id,
                        label: window.kind.heroLabel(for: window.windowDuration),
                        icon: window.kind == .session ? "timer" : "calendar",
                        pct: window.pct,
                        resetText: window.relativeReset,
                        resetDate: window.resetDate,
                        windowDuration: window.windowDuration
                    ), for: .codex)
                })

        case (.pacing, .claude):
            claudePacing
        case (.pacing, .codex):
            codexPacing

        case (.extraCredits, .claude):
            if let extra = usageStore.extraUsage, extra.isEnabled {
                extraUsageTile(extra)
            }
        case (.extraCredits, .codex):
            EmptyView()

        case (.footer, .claude):
            footerPills
        case (.footer, .codex):
            CodexFooterPills()
        }
    }

    /// Stacked in a column, side by side on a single-provider page: the
    /// pacing row has always been two cards abreast and that is the layout
    /// Claude alone keeps.
    @ViewBuilder
    private var claudePacing: some View {
        let cards = [
            usageStore.fiveHourPacing.map {
                (pacing: $0, label: labelled(String(localized: "pacing.session.label"), for: .claude),
                 icon: "clock.fill", workweek: false, cooldown: false)
            },
            usageStore.pacingResult.map {
                (pacing: $0, label: labelled(String(localized: "pacing.weekly.label"), for: .claude),
                 icon: "calendar.badge.clock", workweek: true, cooldown: true)
            },
        ].compactMap { $0 }

        if isComparing {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                pacingCard(pacing: card.pacing, label: card.label, icon: card.icon,
                           showWorkweekBadge: card.workweek, showCooldown: card.cooldown)
            }
        } else {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    pacingCard(pacing: card.pacing, label: card.label, icon: card.icon,
                               showWorkweekBadge: card.workweek, showCooldown: card.cooldown)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var codexPacing: some View {
        let windows = codexStore.windows
            .sorted { $0.windowDuration < $1.windowDuration }
            .filter { $0.pacing != nil }
        if isComparing {
            ForEach(windows) { window in
                CodexPacingCard(
                    pacing: window.pacing!,
                    windowLabel: labelled(window.kind.heroLabel(for: window.windowDuration), for: .codex),
                    isSession: window.kind == .session
                )
            }
        } else {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(windows) { window in
                    CodexPacingCard(
                        pacing: window.pacing!,
                        windowLabel: labelled(window.kind.heroLabel(for: window.windowDuration), for: .codex),
                        isSession: window.kind == .session
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Which tile the Claude hero is already showing, so the grid can skip it.
    /// Nil when the hero shows the 5-hour window, which has no tile of its own
    /// in the grid, so nothing is filtered out.
    private var claudeHeroTileID: String? {
        claudeHeroWindow == .weekly ? "weekly" : nil
    }

    private var codexHeroWindow: CodexWindowSnapshot? {
        if let pinned = settingsStore.heroWindow(for: .codex),
           let match = codexStore.windows.first(where: { $0.kind.rawValue == pinned }) {
            return match
        }
        return codexStore.windows.min { $0.windowDuration < $1.windowDuration }
    }

    /// One rule for every card label on this page: name the provider when
    /// there is another one on screen, never when there is not.
    private func labelled(_ base: String, for provider: MetricProvider) -> String {
        isComparing ? provider.displayName + " · " + base : base
    }

    private func labelled(_ tile: TileDescriptor, for provider: MetricProvider) -> TileDescriptor {
        var copy = tile
        copy.label = labelled(tile.label, for: provider)
        return copy
    }

    // MARK: - Header

    @ViewBuilder
    private var providerBadges: some View {
        HStack(spacing: 5) {
            if showsClaude, usageStore.planType != .unknown {
                planBadge(.claude, usageStore.planType.displayLabel, DS.Palette.brandPrimary)
            }
            if showsCodex, codexStore.planType != .unknown {
                planBadge(.codex, codexStore.planType.displayLabel, codexStore.planType.badgeColor)
            }
        }
    }

    private func planBadge(_ provider: MetricProvider, _ plan: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            ProviderGlyph(provider: provider, size: 10)
            Text(plan)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
        }
        .foregroundStyle(DS.Palette.textPrimary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                .fill(tint.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                        .stroke(tint.opacity(0.45), lineWidth: 0.6)
                )
        )
    }

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

            // The plan badge, the freshness and the refresh button used to sit
            // here, which quietly made this Claude's header as well as the
            // app's. They now live in each provider's section header.

            // The plan badges used to live in a per-provider section bar that
            // only existed in a provider mode, so switching modes added and
            // removed a whole row and shifted the page. They sit here in every
            // mode instead, and the refresh stays far right in all three.
            providerBadges

            if vendorStatusStore.isDegraded, let status = vendorStatusStore.claudeStatus {
                statusPill(status)
            }

            Spacer()

            // Always present now. It was gated on having two providers back
            // when each provider's own bar carried a refresh of its own; those
            // bars are gone, so gating it left a provider mode with no way to
            // refresh at all. It refreshes whatever is visible, which in a
            // provider mode is that one provider.
            if !visibleProviders.isEmpty {
                Button {
                    for provider in visibleProviders {
                        switch provider {
                        case .claude: Task { await usageStore.refresh(force: true) }
                        case .codex:  Task { await codexStore.refresh(force: true) }
                        }
                    }
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
                .help(String(localized: "dashboard.refreshAll"))
                .onHover { hovering in
                    withAnimation(DS.Motion.springSnap) { refreshHovering = hovering }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    /// Compact Claude service-status pill, shown inline in the header only when
    /// Claude is degraded/down. Living in the header (instead of a full-width
    /// card below it) keeps it from adding a row that could push the dashboard
    /// into scrolling. Links to the status page; the incident name is in the
    /// tooltip, and the tint scales orange (degraded) -> red (down).
    @ViewBuilder
    private func statusPill(_ status: VendorStatus) -> some View {
        let tint = status.health == .down ? DS.Palette.semanticError : DS.Palette.semanticWarning
        let label = status.health == .down
            ? String(localized: "dashboard.status.down")
            : String(localized: "dashboard.status.degraded")
        Link(destination: status.statusPageURL) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(tint.opacity(0.35), lineWidth: 0.6)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(status.activeIncidents.first?.name ?? label)
    }

    // MARK: - Hero tile (Session 5H)

    private var heroTile: some View {
        let window = claudeHeroWindow
        let isSession = window == .session
        let pct = isSession ? usageStore.fiveHourPct : usageStore.sevenDayPct
        let resetDate = isSession
            ? usageStore.lastUsage?.fiveHour?.resetsAtDate
            : usageStore.lastUsage?.sevenDay?.resetsAtDate
        let resetText = isSession ? usageStore.fiveHourReset : usageStore.sevenDayReset
        let gaugeColor = gaugeColor(pct: pct, resetDate: resetDate, windowDuration: window.duration)
        let gaugeGradient = gaugeGradient(pct: pct, resetDate: resetDate, windowDuration: window.duration)
        let zone = isSession ? usageStore.fiveHourPacing?.zone : usageStore.pacingResult?.zone
        let pacing = isSession ? usageStore.fiveHourPacing : usageStore.pacingResult
        // Ambient tint follows the gauge color so the wash, the big
        // number, and the ring all read as a single signal.
        let accent = gaugeColor

        // The back face is a session trajectory built from `sessionSamples`,
        // which only exists for the 5-hour window. Pinning the card to weekly
        // therefore drops the flip rather than faking a chart, the same call
        // the Codex card already makes for the same reason.
        return Button {
            guard isSession else { return }
            triggerHeroFlip()
        } label: {
            ZStack {
                if heroFlipped && isSession {
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
                        zone: zone,
                        window: window,
                        resetText: resetText,
                        resetDate: resetDate
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
                    // No `.ultraThinMaterial` here, deliberately, and it is
                    // not an oversight to fix. The two glance cards are the
                    // only ones in the app whose width animates, and a
                    // material re-blurs its backdrop on every frame of that
                    // resize, which is what made a mode switch feel like it
                    // was stuttering. It was also buying nothing: behind it
                    // sits `dsWindowBackground`, a two-stop linear gradient,
                    // and a blurred linear gradient is the same gradient. The
                    // 15% the fill lets through shows it directly now.
                    RoundedRectangle(cornerRadius: DS.Radius.cardLg)
                        .fill(DS.Palette.bgElevated.opacity(0.85))
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
    private func heroFrontContent(
        pct: Int, gaugeColor: Color, gaugeGradient: LinearGradient, zone: PacingZone?,
        window: ClaudeHeroWindow, resetText: String, resetDate: Date?
    ) -> some View {
        ProviderHeroFace(
            provider: .claude,
            windowLabel: window.localizedLabel,
            pct: pct,
            gaugeColor: gaugeColor,
            gaugeGradient: gaugeGradient,
            zone: zone,
            resetText: resetText,
            resetDate: resetDate
        )
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
                    ProviderGlyph(provider: .claude, size: 11)
                        .foregroundStyle(gaugeColor)
                        .dsGlow(gaugeColor, radius: 4, opacity: 0.6)
                    Text(MetricProvider.claude.displayName.uppercased() + " · PACING")
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
                        trajectoryColor: gaugeColor,
                        trajectory: PacingSampleBuffer.trajectory(
                            usageStore.sessionSamples,
                            resetDate: usageStore.lastUsage?.fiveHour?.resetsAtDate,
                            windowDuration: 5 * 3600
                        )
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

    private func grid(of tiles: [TileDescriptor]) -> some View {
        // Width-filling rows instead of a fixed 3-column grid: the number of
        // secondary tiles varies (Opus/Cowork are shown only when their
        // API bucket exists), so a fixed grid left an empty trailing cell when
        // the count was not a multiple of 3. Each row's tiles stretch to fill
        // the full width, so there is never a hole regardless of tile count.
        let rows = MetricsGridLayout.rows(tiles)
        return VStack(spacing: DS.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(row, id: \.id) { tile in
                        metricTile(tile)
                    }
                }
            }
        }
    }

    private func metricTile(_ tile: TileDescriptor) -> some View {
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
            )
        ]
        // Sonnet only exists as a dedicated weekly pool on some plans; on the
        // others the API returns no bucket and the tile would sit at a
        // meaningless permanent 0%. Gate it like Opus/Cowork/Fable below.
        if usageStore.hasSonnet {
            tiles.append(TileDescriptor(
                id: "sonnet",
                label: String(localized: "metric.sonnet"),
                icon: "text.quote",
                pct: usageStore.sonnetPct,
                resetText: usageStore.sonnetReset.isEmpty ? nil : usageStore.sonnetReset,
                resetDate: usageStore.lastUsage?.sevenDaySonnet?.resetsAtDate,
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

    private func pacingCard(pacing: PacingResult, label: String, icon: String, showWorkweekBadge: Bool = false, showCooldown: Bool = false) -> some View {
        let tint = themeStore.current.pacingColor(for: pacing.zone)
        let sign = pacing.delta >= 0 ? "+" : ""
        // "back to 0% in 3d 14h" when ahead of pace (#245). Takes the caption
        // line in place of the flavor message: when you're over, the ETA to
        // catch back down is the more useful signal. nil when at/under pace.
        let cooldownText: String? = {
            guard showCooldown, let cooling = pacing.coolingDate else { return nil }
            let relative = ResetCountdownFormatter.weekly(from: cooling).relative
            return relative.isEmpty ? nil : String(format: String(localized: "pacing.cooldown"), relative)
        }()
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

            if let cooldownText {
                Text(cooldownText)
                    .font(DS.Typography.label)
                    .foregroundStyle(tint.opacity(0.85))
                    .lineLimit(1)
            } else if !pacing.message.isEmpty {
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
                DashboardStatusPill(icon: "sparkles", label: String(localized: "dashboard.tier"), value: tier.formattedRateLimitTier, tint: DS.Palette.accentStats)
            }
            if let org = usageStore.organizationName {
                DashboardStatusPill(icon: "building.2.fill", label: String(localized: "dashboard.org"), value: org, tint: DS.Palette.accentHistory)
            }
            Spacer()
        }
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
        ProviderHeroFace.zoneGlyph(for: zone)
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


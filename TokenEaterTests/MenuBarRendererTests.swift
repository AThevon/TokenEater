import Testing
import Foundation
import AppKit

@Suite("MenuBarRenderer.smartResetNSColor")
struct MenuBarRendererTests {

    private let theme = ThemeColors.default
    private let thresholds = UsageThresholds.default // warning: 60, critical: 85
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func reset(_ minutesAway: Double) -> Date {
        now.addingTimeInterval(minutesAway * 60)
    }

    private func color(_ utilization: Double, minutesRemaining: Double) -> NSColor {
        MenuBarRenderer.smartResetNSColor(
            utilization: utilization,
            resetDate: reset(minutesRemaining),
            themeColors: theme,
            thresholds: thresholds,
            now: now
        )
    }

    @Test("limit reached with short remaining stays critical")
    func limitReachedShortRemainingCritical() {
        // Bug repro: utilization 100%, 20 min left -> risk score = 20 which
        // used to map to the normal (green) gauge color. With the fix, any
        // utilization at or above the critical threshold must return the
        // critical color regardless of remaining time.
        let observed = color(100, minutesRemaining: 20)
        let expected = theme.gaugeNSColor(for: 100, thresholds: thresholds)
        #expect(observed == expected)
    }

    @Test("limit reached with long remaining stays critical")
    func limitReachedLongRemainingCritical() {
        let observed = color(95, minutesRemaining: 240)
        let expected = theme.gaugeNSColor(for: 95, thresholds: thresholds)
        #expect(observed == expected)
    }

    @Test("low utilization near reset stays normal")
    func lowUtilizationShortRemainingNormal() {
        // 30% with 15 min left: risk = 4.5 -> normal color.
        let observed = color(30, minutesRemaining: 15)
        let expected = theme.gaugeNSColor(for: 10, thresholds: thresholds)
        #expect(observed == expected)
    }

    @Test("high pre-critical utilization with ample remaining escalates to critical")
    func projectedRiskEscalatesToCritical() {
        // 80% utilization (below critical 85) with 3h left: risk = 144 -> critical band.
        let observed = color(80, minutesRemaining: 180)
        let expected = theme.gaugeNSColor(for: 100, thresholds: thresholds)
        #expect(observed == expected)
    }

    @Test("pre-critical utilization with moderate remaining lands in warning band (v3)")
    func projectedRiskWarning() {
        // v3 model: smart calibration is now profile-driven (Balanced
        // bounds 0.50/1.00 instead of the user's 0.60/0.85 thresholds),
        // and the absolute signal is dampened by projection health
        // (smoothstep(0.7, 1.0, u/e)). At u=0.80 / 90min remaining on
        // 5h: u/e = 0.80/0.90 = 0.889, dampened to ~0.69, multiplied
        // by absolute_raw smoothstep(0.50, 1.00, 0.80) ≈ 0.65 -> final
        // risk ~0.45, which interpolates ~60% of the way from green to
        // orange. So the color is a vivid orange, not red.
        //
        // The pre-v3 expectation of "stays critical at 80% / 90min" was
        // a v2-era fix for v1's reset-imminent override; v3's projection-
        // health damping makes 80% with calm pacing legitimately less
        // alarming because the user is on track to finish ~89% of limit.
        let observed = color(80, minutesRemaining: 90)
        // The 98%/30min hard flag is preserved separately; here we just
        // assert the color sits in the green-to-orange interpolation
        // region rather than matching threshold-mode red.
        let red = theme.gaugeNSColor(for: 95, thresholds: thresholds)
        #expect(observed != red, "80% / 90min should no longer match the threshold-mode red color")
    }
}

@Suite("MenuBarRenderer.outageBadge")
struct MenuBarOutageBadgeTests {

    static func sampleRenderData(
        segments: [MenuBarSegment] = [MenuBarSegment(kind: .session, style: .labelValue)],
        outageActive: Bool = false,
        outageHealth: VendorHealth = .healthy,
        nextPollSeconds: Int? = nil
    ) -> MenuBarRenderer.RenderData {
        MenuBarRenderer.RenderData(
            composition: MenuBarComposition(segments: segments),
            fiveHourPct: 10,
            sevenDayPct: 5,
            sonnetPct: 0,
            weeklyPacingDelta: 0,
            weeklyPacingZone: .onTrack,
            hasWeeklyPacing: false,
            sessionPacingDelta: 0,
            sessionPacingZone: .onTrack,
            hasSessionPacing: false,
            fablePacingDelta: 0,
            fablePacingZone: .onTrack,
            hasFablePacing: false,
            hasConfig: true,
            hasError: false,
            isAwaitingRefresh: false,
            themeColors: .default,
            thresholds: .default,
            menuBarMonochrome: false,
            fiveHourReset: "",
            fiveHourResetAbsolute: "",
            fiveHourResetDate: nil,
            sevenDayResetDate: nil,
            sonnetResetDate: nil,
            hasFiveHourBucket: true,
            resetTextColorHex: "",
            sessionPeriodColorHex: "",
            smartResetColor: false,
            smartColorProfile: .balanced,
            pacingMargin: 10,
            fablePct: 0,
            hasFable: false,
            fableResetDate: nil,
            outageActive: outageActive,
            outageHealth: outageHealth,
            nextPollSeconds: nextPollSeconds,
            extraCreditsPct: 0,
            hasExtraCredits: false,
            extraCreditsUncappedSpend: nil,
            extraCreditsUncappedHasSpend: false,
            codexSession: nil, codexWeekly: nil,
            visibleProviders: [.claude, .codex]
        )
    }

    @Test("outage badge widens the rendered image vs. no badge")
    func outageBadgeRenders() {
        // Build two RenderData values identical except for the outage badge.
        // Reuse however this suite already builds RenderData; only the three
        // new fields differ.
        let base = Self.sampleRenderData(outageActive: false)
        let badged = Self.sampleRenderData(outageActive: true, outageHealth: .down, nextPollSeconds: 65)

        let baseImg = MenuBarRenderer.renderUncached(base)
        let badgedImg = MenuBarRenderer.renderUncached(badged)

        #expect(badgedImg.isTemplate == false)
        #expect(badgedImg.size.width > baseImg.size.width)
    }

    @Test("pinned serviceStatus with .down is non-template and wider than .healthy")
    func pinnedServiceStatusDownWiderThanHealthy() {
        let healthy = Self.sampleRenderData(
            segments: [MenuBarSegment(kind: .serviceStatus, style: .glyph)],
            outageHealth: .healthy,
            nextPollSeconds: nil
        )
        let down = Self.sampleRenderData(
            segments: [MenuBarSegment(kind: .serviceStatus, style: .glyph)],
            outageHealth: .down,
            nextPollSeconds: 125
        )

        let healthyImg = MenuBarRenderer.renderUncached(healthy)
        let downImg = MenuBarRenderer.renderUncached(down)

        #expect(downImg.isTemplate == false)
        #expect(downImg.size.width > healthyImg.size.width)
    }
}

@Suite("MenuBarRenderer.periodLabelColor")
struct MenuBarPeriodLabelColorTests {

    @Test("default (no custom hex) is the legible secondary colour, not the faint tertiary")
    func defaultIsLegible() {
        let resolved = MenuBarRenderer.periodLabelColor(hex: "")
        #expect(resolved == MenuBarRenderer.defaultPeriodLabelColor)
        // Regression guard for #196: the "5h" / "7d" label used to default to
        // tertiary (~26%), nearly invisible on a light menu bar. It must not
        // revert to that faint grey.
        #expect(MenuBarRenderer.defaultPeriodLabelColor != NSColor.tertiaryLabelColor)
    }

    /// A user-picked hex wins. The resolver is mode-agnostic, so the same colour
    /// applies in monochrome too (the #196 promise: tweakable in monochrome).
    @Test("a valid custom hex overrides the default")
    func customHexWins() {
        let resolved = MenuBarRenderer.periodLabelColor(hex: "#3366FF")
        #expect(resolved == MenuBarTextColorResolver.resolve(hex: "#3366FF", fallback: .clear))
        #expect(resolved != MenuBarRenderer.defaultPeriodLabelColor)
    }

    @Test("empty or malformed hex falls back to the legible default")
    func malformedHexFallsBack() {
        #expect(MenuBarRenderer.periodLabelColor(hex: "   ") == MenuBarRenderer.defaultPeriodLabelColor)
        #expect(MenuBarRenderer.periodLabelColor(hex: "not-a-color") == MenuBarRenderer.defaultPeriodLabelColor)
    }
}

/// Covers the windowless-metric colouring rule that keeps Extra Credits in
/// agreement across the menu bar, popover, dashboard and widgets: Smart Color
/// is time-aware, so a metric with no reset window must use the static
/// threshold ladder instead of the profile-based absolute-risk colour.
@Suite("MenuBarRenderer.gaugeColor (windowless fallback)")
struct MenuBarGaugeColorTests {

    private let theme = ThemeColors.default
    private let thresholds = UsageThresholds.default // warning 60, critical 85
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("windowless metric uses the threshold ladder even when Smart Color is on")
    func windowlessUsesThresholds() {
        // Extra Credits has no reset window (resetDate nil, windowDuration 0).
        let observed = MenuBarRenderer.gaugeColor(
            pct: 67, resetDate: nil, windowDuration: 0,
            monochrome: false, smartEnabled: true,
            themeColors: theme, thresholds: thresholds,
            pacingMargin: 10, smartColorProfile: .balanced, now: now
        )
        // 67% is past the 60 warning threshold → warning colour.
        #expect(observed == theme.gaugeNSColor(for: 67, thresholds: thresholds))
        // Regression guard for the green-vs-orange bug: the old code routed
        // windowless metrics through Smart Color, which reads a calmer colour
        // at 67% because the profile bounds (≈0.50/1.00) differ from the user's
        // 60/85 thresholds. Those two colours must NOT be equal here.
        let smartWindowless = theme.smartGaugeNSColor(
            utilization: 67, resetDate: nil, windowDuration: 0,
            thresholds: thresholds, pacingMargin: 10, now: now, profile: .balanced
        )
        #expect(observed != smartWindowless)
    }

    @Test("windowed metric still uses Smart Color when enabled")
    func windowedUsesSmart() {
        let reset = now.addingTimeInterval(180 * 60) // 3h left on a 5h window
        let observed = MenuBarRenderer.gaugeColor(
            pct: 80, resetDate: reset, windowDuration: 5 * 3600,
            monochrome: false, smartEnabled: true,
            themeColors: theme, thresholds: thresholds,
            pacingMargin: 10, smartColorProfile: .balanced, now: now
        )
        let expectedSmart = theme.smartGaugeNSColor(
            utilization: 80, resetDate: reset, windowDuration: 5 * 3600,
            thresholds: thresholds, pacingMargin: 10, now: now, profile: .balanced
        )
        #expect(observed == expectedSmart)
    }

    @Test("smart disabled always uses the threshold ladder")
    func smartDisabledUsesThresholds() {
        let reset = now.addingTimeInterval(180 * 60)
        let observed = MenuBarRenderer.gaugeColor(
            pct: 80, resetDate: reset, windowDuration: 5 * 3600,
            monochrome: false, smartEnabled: false,
            themeColors: theme, thresholds: thresholds,
            pacingMargin: 10, smartColorProfile: .balanced, now: now
        )
        #expect(observed == theme.gaugeNSColor(for: 80, thresholds: thresholds))
    }

    @Test("monochrome wins over everything")
    func monochromeWins() {
        let observed = MenuBarRenderer.gaugeColor(
            pct: 67, resetDate: nil, windowDuration: 0,
            monochrome: true, smartEnabled: true,
            themeColors: theme, thresholds: thresholds,
            pacingMargin: 10, smartColorProfile: .balanced, now: now
        )
        #expect(observed == NSColor.labelColor)
    }
}

/// Covers the pin gating: Extra Credits renders in the menu bar only when the
/// paid pool is enabled, otherwise the item must not silently vanish.
@Suite("MenuBarRenderer Extra Credits gating")
struct MenuBarExtraCreditsRenderTests {

    /// Full RenderData with neutral defaults; tests override only what matters.
    private func data(
        segments: [MenuBarSegment] = [MenuBarSegment(kind: .extraCredits, style: .labelValue)],
        hasExtraCredits: Bool = true,
        extraCreditsPct: Int = 67,
        uncappedSpend: String? = nil,
        uncappedHasSpend: Bool = false,
        monochrome: Bool = false
    ) -> MenuBarRenderer.RenderData {
        MenuBarRenderer.RenderData(
            composition: MenuBarComposition(segments: segments),
            fiveHourPct: 0, sevenDayPct: 0, sonnetPct: 0,
            weeklyPacingDelta: 0, weeklyPacingZone: .onTrack, hasWeeklyPacing: false,
            sessionPacingDelta: 0, sessionPacingZone: .onTrack, hasSessionPacing: false,
            fablePacingDelta: 0, fablePacingZone: .onTrack, hasFablePacing: false,
            hasConfig: true, hasError: false, isAwaitingRefresh: false,
            themeColors: .default, thresholds: .default,
            menuBarMonochrome: monochrome,
            fiveHourReset: "", fiveHourResetAbsolute: "",
            fiveHourResetDate: nil, sevenDayResetDate: nil, sonnetResetDate: nil,
            hasFiveHourBucket: false,
            resetTextColorHex: "", sessionPeriodColorHex: "",
            smartResetColor: false, smartColorProfile: .balanced,
            pacingMargin: 10,
            fablePct: 0, hasFable: false, fableResetDate: nil,
            outageActive: false, outageHealth: .healthy, nextPollSeconds: nil,
            extraCreditsPct: extraCreditsPct, hasExtraCredits: hasExtraCredits,
            extraCreditsUncappedSpend: uncappedSpend,
            extraCreditsUncappedHasSpend: uncappedHasSpend,
            codexSession: nil, codexWeekly: nil,
            visibleProviders: [.claude, .codex]
        )
    }

    @Test("EC segment + pool enabled renders a value (non-template image)")
    func renderedWhenEnabled() {
        let image = MenuBarRenderer.renderUncached(data(hasExtraCredits: true))
        // The composition path produces a non-template text image; the logo
        // fallback is a template. So a non-template image proves EC drew.
        #expect(image.isTemplate == false)
        #expect(image.size.width > 0)
    }

    @Test("EC segment but pool disabled falls back to the logo (template image)")
    func logoFallbackWhenDisabled() {
        // Only EC is in the composition and it's filtered out → no visible
        // segment → the renderer returns the template logo, not a 0-width sliver.
        let image = MenuBarRenderer.renderUncached(data(hasExtraCredits: false))
        #expect(image.isTemplate == true)
    }

    @Test("EC renders in pill style too")
    func renderedInPillStyle() {
        let image = MenuBarRenderer.renderUncached(
            data(segments: [MenuBarSegment(kind: .extraCredits, style: .pill)], hasExtraCredits: true)
        )
        #expect(image.isTemplate == false)
        #expect(image.size.width > 0)
    }

    /// No monthly limit: the segment draws the amount spent where the
    /// percentage was. A wider image than the same segment's "0%" proves the
    /// amount replaced it, in every style that shows a value.
    @Test("uncapped EC draws the amount spent instead of 0%", arguments: [
        MenuBarSegmentStyle.labelValue, .valueOnly, .mono, .pill,
    ])
    func uncappedDrawsSpend(style: MenuBarSegmentStyle) {
        let segments = [MenuBarSegment(kind: .extraCredits, style: style)]
        let percent = MenuBarRenderer.renderUncached(data(segments: segments, extraCreditsPct: 0))
        let spend = MenuBarRenderer.renderUncached(
            data(segments: segments, extraCreditsPct: 0, uncappedSpend: "$1,235")
        )
        #expect(spend.isTemplate == false)
        #expect(spend.size.width > percent.size.width)
    }

    /// A monthly limit keeps the percentage. The data comes from a real
    /// capped pool ($268 of $400), so it carries no spend text; in monochrome
    /// (where both paths use `labelColor`) its segment is pixel-identical to
    /// one whose value text is literally "67%", which proves the capped
    /// segment prints its percentage and not an amount.
    @Test("capped EC keeps rendering the percentage", arguments: [
        MenuBarSegmentStyle.labelValue, .valueOnly, .pill,
    ])
    func cappedKeepsPercent(style: MenuBarSegmentStyle) {
        let pool = ExtraUsage(
            isEnabled: true, monthlyLimit: 40000, usedCredits: 26800,
            utilization: nil, currency: "USD", disabledReason: nil
        )
        #expect(pool.uncappedSpendText == nil)
        #expect(pool.percent == 67)

        let segments = [MenuBarSegment(kind: .extraCredits, style: style)]
        let capped = MenuBarRenderer.renderUncached(data(
            segments: segments, extraCreditsPct: pool.percent,
            uncappedSpend: pool.uncappedSpendText, monochrome: true
        ))
        let reference = MenuBarRenderer.renderUncached(data(
            segments: segments, extraCreditsPct: 0,
            uncappedSpend: "67%", monochrome: true
        ))
        #expect(capped.size == reference.size)
        #expect(capped.tiffRepresentation == reference.tiffRepresentation)
    }

    /// Uncapped with nothing spent: plain information, the neutral label
    /// colour, like the dashboard card's $0.
    @Test("uncapped EC with nothing spent is neutral")
    func uncappedZeroIsNeutral() {
        let color = MenuBarRenderer.uncappedSpendColor(
            hasSpend: false, monochrome: false, themeColors: .default, thresholds: .default
        )
        #expect(color == NSColor.labelColor)
    }

    /// Uncapped with real money spent: the theme's warning gauge colour, the
    /// one the dashboard card uses, so every surface colours the spend alike.
    @Test("uncapped EC with money spent takes the warning colour")
    func uncappedSpentIsWarning() {
        let thresholds = UsageThresholds.default
        let color = MenuBarRenderer.uncappedSpendColor(
            hasSpend: true, monochrome: false, themeColors: .default, thresholds: thresholds
        )
        #expect(color == ThemeColors.default.gaugeNSColor(for: Double(thresholds.warningPercent), thresholds: thresholds))
        #expect(color == NSColor(hex: ThemeColors.default.gaugeWarning))
        #expect(color != NSColor.labelColor)
    }

    /// Monochrome stays monochrome for the uncapped spend, like every other
    /// segment.
    @Test("uncapped EC spend stays monochrome in monochrome mode")
    func uncappedSpentMonochrome() {
        let color = MenuBarRenderer.uncappedSpendColor(
            hasSpend: true, monochrome: true, themeColors: .default, thresholds: .default
        )
        #expect(color == NSColor.labelColor)
    }

    /// End to end through the renderer: the same amount draws differently
    /// once it counts as spent (warning colour instead of the label colour),
    /// in every style, and identically in monochrome.
    @Test("uncapped EC segment recolours once money is spent", arguments: [
        MenuBarSegmentStyle.labelValue, .valueOnly, .mono, .pill,
    ])
    func uncappedSegmentRecolours(style: MenuBarSegmentStyle) {
        let segments = [MenuBarSegment(kind: .extraCredits, style: style)]
        func render(hasSpend: Bool, monochrome: Bool) -> NSImage {
            MenuBarRenderer.renderUncached(data(
                segments: segments, extraCreditsPct: 0, uncappedSpend: "$20.49",
                uncappedHasSpend: hasSpend, monochrome: monochrome
            ))
        }
        let zero = render(hasSpend: false, monochrome: false)
        let spent = render(hasSpend: true, monochrome: false)
        #expect(zero.size == spent.size)
        #expect(zero.tiffRepresentation != spent.tiffRepresentation)
        #expect(render(hasSpend: false, monochrome: true).tiffRepresentation
            == render(hasSpend: true, monochrome: true).tiffRepresentation)
    }

    /// The spend only ever replaces the Extra Credits value, never another
    /// segment's percentage.
    @Test("uncapped spend does not leak into other segments")
    func spendScopedToExtraCredits() {
        let segments = [MenuBarSegment(kind: .session, style: .labelValue)]
        let without = MenuBarRenderer.renderUncached(data(segments: segments))
        let with = MenuBarRenderer.renderUncached(data(segments: segments, uncappedSpend: "$1,235"))
        #expect(without.tiffRepresentation == with.tiffRepresentation)
    }
}

/// Fable pacing 3-state gating (#241 + idle status): absent (no Fable bucket)
/// draws nothing; idle (bucket present, no active window) draws a placeholder;
/// active draws the shape + delta.
@Suite("MenuBarRenderer Fable pacing idle/absent gating")
struct MenuBarFablePacingRenderTests {

    private func data(
        hasFable: Bool,
        hasFablePacing: Bool
    ) -> MenuBarRenderer.RenderData {
        MenuBarRenderer.RenderData(
            composition: MenuBarComposition(segments: [MenuBarSegment(kind: .fablePacing, style: .dotDelta)]),
            fiveHourPct: 0, sevenDayPct: 0, sonnetPct: 0,
            weeklyPacingDelta: 0, weeklyPacingZone: .onTrack, hasWeeklyPacing: false,
            sessionPacingDelta: 0, sessionPacingZone: .onTrack, hasSessionPacing: false,
            fablePacingDelta: 12, fablePacingZone: .warning, hasFablePacing: hasFablePacing,
            hasConfig: true, hasError: false, isAwaitingRefresh: false,
            themeColors: .default, thresholds: .default,
            menuBarMonochrome: false,
            fiveHourReset: "", fiveHourResetAbsolute: "",
            fiveHourResetDate: nil, sevenDayResetDate: nil, sonnetResetDate: nil,
            hasFiveHourBucket: false,
            resetTextColorHex: "", sessionPeriodColorHex: "",
            smartResetColor: false, smartColorProfile: .balanced,
            pacingMargin: 10,
            fablePct: 0, hasFable: hasFable, fableResetDate: nil,
            outageActive: false, outageHealth: .healthy, nextPollSeconds: nil,
            extraCreditsPct: 0, hasExtraCredits: false, extraCreditsUncappedSpend: nil,
            extraCreditsUncappedHasSpend: false,
            codexSession: nil, codexWeekly: nil,
            visibleProviders: [.claude, .codex]
        )
    }

    @Test("Fable pacing absent (no bucket) -> only segment filtered out -> logo fallback")
    func absentDrawsNothing() {
        let image = MenuBarRenderer.renderUncached(data(hasFable: false, hasFablePacing: false))
        #expect(image.isTemplate == true) // logo template = nothing drawable
    }

    @Test("Fable pacing idle (bucket present, no window) -> placeholder renders")
    func idleDrawsPlaceholder() {
        let image = MenuBarRenderer.renderUncached(data(hasFable: true, hasFablePacing: false))
        #expect(image.isTemplate == false) // a real (non-logo) segment drew
        #expect(image.size.width > 0)
    }

    @Test("Fable pacing active (bucket + window) -> shape + delta renders")
    func activeDrawsPacing() {
        let image = MenuBarRenderer.renderUncached(data(hasFable: true, hasFablePacing: true))
        #expect(image.isTemplate == false)
        #expect(image.size.width > 0)
    }
}

@Suite("MenuBarRenderer.accounts")
struct MenuBarAccountSegmentTests {

    private let work = AccountID(rawValue: "acct-work")

    private func data(_ segments: [MenuBarSegment]) -> MenuBarRenderer.RenderData {
        MenuBarOutageBadgeTests.sampleRenderData(segments: segments)
    }

    @Test("a segment pinned to a running account reads that account's numbers")
    func pinnedSegmentReadsItsAccount() {
        var bar = data([
            MenuBarSegment(kind: .session, style: .labelValue),
            MenuBarSegment(kind: .session, style: .labelValue, account: work),
        ])
        var account = bar
        account.composition = MenuBarComposition(segments: [])
        bar.accountData[work.rawValue] = account

        let pinned = bar.composition.segments[1]
        #expect(MenuBarRenderer.source(for: pinned, data: bar) == account)
        #expect(MenuBarRenderer.source(for: bar.composition.segments[0], data: bar) == bar)
        #expect(MenuBarRenderer.renderWithHitRects(bar).hitRects.count == 2)
    }

    @Test("a segment whose account is not running draws nothing and the bar closes up")
    func missingAccountIsSkipped() {
        let bar = data([
            MenuBarSegment(kind: .session, style: .labelValue),
            MenuBarSegment(kind: .weekly, style: .labelValue, account: work),
        ])
        let rects = MenuBarRenderer.renderWithHitRects(bar).hitRects
        #expect(rects.map(\.id) == [bar.composition.segments[0].id])
    }

    @Test("an explicit main account and the Codex kinds read the bar's own numbers")
    func mainAndCodexIgnoreAccounts() {
        let bar = data([
            MenuBarSegment(kind: .session, style: .labelValue, account: .main),
            MenuBarSegment(kind: .serviceStatus, style: .glyph, account: work),
        ])
        for segment in bar.composition.segments {
            #expect(MenuBarRenderer.source(for: segment, data: bar) == bar)
        }
    }

    @Test("a single account renders exactly as before")
    func singleAccountUnchanged() {
        let bar = data([
            MenuBarSegment(kind: .session, style: .labelValue),
            MenuBarSegment(kind: .weekly, style: .pill),
        ])
        var withEmptyAccounts = bar
        withEmptyAccounts.accountData = [:]
        #expect(withEmptyAccounts == bar)
        let before = MenuBarRenderer.renderWithHitRects(bar)
        #expect(before.hitRects.count == 2)
        #expect(MenuBarRenderer.renderUncached(bar).size == before.image.size)
    }

    @Test("an account with no numbers yet shows a placeholder, never a 0%")
    func placeholderWidth() {
        let segment = MenuBarSegment(kind: .session, style: .valueOnly)
        var placeholder = data([segment])
        placeholder.showsPlaceholderValues = true
        let real = data([segment])
        // "--" and "10%" are different runs: the placeholder is not the value.
        #expect(MenuBarRenderer.renderUncached(placeholder).size != MenuBarRenderer.renderUncached(real).size)
        #expect(placeholder != real)
    }
}

@Suite("MenuBarRenderer.accountMarkers")
struct MenuBarAccountMarkerTests {

    private let work = AccountID(rawValue: "acct-work")
    private let main = AccountID.main.rawValue

    private func twoAccounts(
        _ segments: [MenuBarSegment],
        label: MenuBarAccountLabel = .dotAndName,
        monochrome: Bool = false
    ) -> MenuBarRenderer.RenderData {
        var bar = MenuBarOutageBadgeTests.sampleRenderData(segments: segments)
        bar.composition.accountLabel = label
        if monochrome {
            bar = MenuBarRenderer.RenderData(
                composition: bar.composition, fiveHourPct: 10, sevenDayPct: 5, sonnetPct: 0,
                weeklyPacingDelta: 0, weeklyPacingZone: .onTrack, hasWeeklyPacing: false,
                sessionPacingDelta: 0, sessionPacingZone: .onTrack, hasSessionPacing: false,
                fablePacingDelta: 0, fablePacingZone: .onTrack, hasFablePacing: false,
                hasConfig: true, hasError: false, isAwaitingRefresh: false,
                themeColors: .default, thresholds: .default, menuBarMonochrome: true,
                fiveHourReset: "", fiveHourResetAbsolute: "", fiveHourResetDate: nil,
                sevenDayResetDate: nil, sonnetResetDate: nil, hasFiveHourBucket: true,
                resetTextColorHex: "", sessionPeriodColorHex: "", smartResetColor: false,
                smartColorProfile: .balanced, pacingMargin: 10, fablePct: 0, hasFable: false,
                fableResetDate: nil, outageActive: false, outageHealth: .healthy, nextPollSeconds: nil,
                extraCreditsPct: 0, hasExtraCredits: false, extraCreditsUncappedSpend: nil,
                extraCreditsUncappedHasSpend: false, codexSession: nil, codexWeekly: nil,
                visibleProviders: [.claude, .codex]
            )
        }
        var account = bar
        account.composition = MenuBarComposition(segments: [])
        bar.accountData[work.rawValue] = account
        bar.accountMarkers = [
            main: MenuBarRenderer.AccountMarker(label: "Perso", colorHex: "#5B8DEF"),
            work.rawValue: MenuBarRenderer.AccountMarker(label: "Work", colorHex: "#F472B6"),
        ]
        return bar
    }

    @Test("Every session style gets exactly one marker per account run, the main account's included")
    func oneMarkerPerRunInEveryStyle() {
        for style in MenuBarSegmentKind.session.allowedStyles {
            let segments = [
                MenuBarSegment(kind: .session, style: style),
                MenuBarSegment(kind: .weekly, style: .labelValue),
                MenuBarSegment(kind: .session, style: style, account: work),
                MenuBarSegment(kind: .weekly, style: .labelValue, account: work),
            ]
            let bar = twoAccounts(segments)
            #expect(MenuBarRenderer.layoutPlan(bar) == [
                .marker(main), .segment(segments[0].id), .segment(segments[1].id),
                .marker(work.rawValue), .segment(segments[2].id), .segment(segments[3].id),
            ], "style \(style)")
            // Markers belong to the segment they precede: one hit rect per
            // segment, the first of each run starting at the marker.
            let rects = MenuBarRenderer.renderWithHitRects(bar).hitRects
            #expect(rects.map(\.id) == segments.map(\.id))
            #expect(rects.first?.rect.minX == 1)
        }
    }

    @Test("A single account plans its segments alone and draws exactly as before")
    func singleAccountHasNoMarkers() {
        let segments = [
            MenuBarSegment(kind: .session, style: .labelValue),
            MenuBarSegment(kind: .weekly, style: .pill),
        ]
        let bar = MenuBarOutageBadgeTests.sampleRenderData(segments: segments)
        #expect(MenuBarRenderer.layoutPlan(bar) == segments.map { .segment($0.id) })
        var marked = twoAccounts(segments)
        #expect(MenuBarRenderer.renderUncached(marked).size.width > MenuBarRenderer.renderUncached(bar).size.width)
        // Without the markers (one running account) the two are the same bar.
        marked.accountMarkers = [:]
        marked.accountData = [:]
        #expect(marked == bar)
        #expect(MenuBarRenderer.renderUncached(marked).size == MenuBarRenderer.renderUncached(bar).size)
    }

    @Test("A segment of a paused or removed account is not planned, nor is its marker")
    func pausedAccountIsNotPlanned() {
        let segments = [
            MenuBarSegment(kind: .session, style: .labelValue),
            MenuBarSegment(kind: .session, style: .labelValue, account: AccountID(rawValue: "acct-gone")),
        ]
        let bar = twoAccounts(segments)
        #expect(MenuBarRenderer.layoutPlan(bar) == [.marker(main), .segment(segments[0].id)])
    }

    @Test("Codex and neutral segments end a run, so a split account is marked again")
    func codexEndsARun() {
        let segments = [
            MenuBarSegment(kind: .session, style: .labelValue),
            MenuBarSegment(kind: .serviceStatus, style: .glyph),
            MenuBarSegment(kind: .weekly, style: .labelValue),
        ]
        let bar = twoAccounts(segments)
        #expect(MenuBarRenderer.layoutPlan(bar) == [
            .marker(main), .segment(segments[0].id), .segment(segments[1].id),
            .marker(main), .segment(segments[2].id),
        ])
    }

    @Test("Claude mode on an added account: segments with no account read that account")
    func focusedAccountIsTheDefault() {
        let segments = [MenuBarSegment(kind: .session, style: .valueOnly)]
        var bar = twoAccounts(segments)
        bar.defaultAccount = work.rawValue
        #expect(MenuBarRenderer.source(for: segments[0], data: bar) == bar.accountData[work.rawValue])
        #expect(MenuBarRenderer.layoutPlan(bar) == [.marker(work.rawValue), .segment(segments[0].id)])
        // An explicit main account still reads the main account.
        let pinned = MenuBarSegment(kind: .session, style: .valueOnly, account: .main)
        #expect(MenuBarRenderer.source(for: pinned, data: bar) == bar)
    }

    @Test("A monochrome bar spells the names even when set to dots")
    func monochromeForcesNames() {
        let segments = [
            MenuBarSegment(kind: .session, style: .valueOnly),
            MenuBarSegment(kind: .session, style: .valueOnly, account: work),
        ]
        let dots = MenuBarRenderer.renderUncached(twoAccounts(segments, label: .dot)).size.width
        let named = MenuBarRenderer.renderUncached(twoAccounts(segments, label: .dotAndName)).size.width
        let monoDots = MenuBarRenderer.renderUncached(twoAccounts(segments, label: .dot, monochrome: true)).size.width
        #expect(named > dots)
        #expect(monoDots == named)
    }

    @Test("A name longer than eight characters is cut with an ellipsis in the bar")
    func longNamesAreShortened() {
        let segments = [
            MenuBarSegment(kind: .session, style: .valueOnly),
            MenuBarSegment(kind: .session, style: .valueOnly, account: work),
        ]
        var long = twoAccounts(segments)
        long.accountMarkers[work.rawValue] = MenuBarRenderer.AccountMarker(label: "Personnelle", colorHex: "#F472B6")
        var cut = long
        cut.accountMarkers[work.rawValue] = MenuBarRenderer.AccountMarker(label: "Personne…", colorHex: "#F472B6")
        #expect(MenuBarRenderer.renderUncached(long).size == MenuBarRenderer.renderUncached(cut).size)
    }

    @Test("With several accounts, one without numbers shows a placeholder and the bar keeps the others")
    func accountWithoutNumbersKeepsTheBar() {
        let segments = [
            MenuBarSegment(kind: .session, style: .valueOnly),
            MenuBarSegment(kind: .session, style: .valueOnly, account: work),
        ]
        var bar = twoAccounts(segments)
        bar.accountData[work.rawValue]?.hasNumbers = false
        #expect(MenuBarRenderer.renderWithHitRects(bar).hitRects.count == 2)

        // The main account with no token at all no longer hides Work.
        var noMainToken = twoAccounts(segments)
        noMainToken = MenuBarRenderer.RenderData(
            composition: noMainToken.composition, fiveHourPct: 0, sevenDayPct: 0, sonnetPct: 0,
            weeklyPacingDelta: 0, weeklyPacingZone: .onTrack, hasWeeklyPacing: false,
            sessionPacingDelta: 0, sessionPacingZone: .onTrack, hasSessionPacing: false,
            fablePacingDelta: 0, fablePacingZone: .onTrack, hasFablePacing: false,
            hasConfig: false, hasError: true, isAwaitingRefresh: false,
            themeColors: .default, thresholds: .default, menuBarMonochrome: false,
            fiveHourReset: "", fiveHourResetAbsolute: "", fiveHourResetDate: nil,
            sevenDayResetDate: nil, sonnetResetDate: nil, hasFiveHourBucket: true,
            resetTextColorHex: "", sessionPeriodColorHex: "", smartResetColor: false,
            smartColorProfile: .balanced, pacingMargin: 10, fablePct: 0, hasFable: false,
            fableResetDate: nil, outageActive: false, outageHealth: .healthy, nextPollSeconds: nil,
            extraCreditsPct: 0, hasExtraCredits: false, extraCreditsUncappedSpend: nil,
            extraCreditsUncappedHasSpend: false, codexSession: nil, codexWeekly: nil,
            visibleProviders: [.claude, .codex],
            accountData: noMainToken.accountData,
            accountMarkers: noMainToken.accountMarkers,
            hasNumbers: false
        )
        #expect(MenuBarRenderer.renderWithHitRects(noMainToken).hitRects.count == 2)
        // Alone, the same main account shows the logo, as it always did.
        var alone = noMainToken
        alone.accountMarkers = [:]
        alone.accountData = [:]
        #expect(MenuBarRenderer.renderWithHitRects(alone).hitRects.isEmpty)
    }

    @Test("The render cache tells two bars apart by their accounts' numbers")
    func cacheSeesAccountData() {
        let segments = [MenuBarSegment(kind: .session, style: .valueOnly, account: work)]
        let bar = twoAccounts(segments)
        var changed = bar
        changed.accountData[work.rawValue]?.showsPlaceholderValues = true
        #expect(bar != changed)
        var relabelled = bar
        relabelled.accountMarkers[work.rawValue] = MenuBarRenderer.AccountMarker(label: "Side", colorHex: "#22D3EE")
        #expect(bar != relabelled)
    }
}

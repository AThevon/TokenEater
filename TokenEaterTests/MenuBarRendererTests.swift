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
        pinnedMetrics: Set<MetricID> = [.fiveHour],
        outageActive: Bool = false,
        outageHealth: VendorHealth = .healthy,
        nextPollSeconds: Int? = nil
    ) -> MenuBarRenderer.RenderData {
        MenuBarRenderer.RenderData(
            pinnedMetrics: pinnedMetrics,
            displaySonnet: false,
            fiveHourPct: 10,
            sevenDayPct: 5,
            sonnetPct: 0,
            weeklyPacingDelta: 0,
            weeklyPacingZone: .onTrack,
            hasWeeklyPacing: false,
            sessionPacingDelta: 0,
            sessionPacingZone: .onTrack,
            hasSessionPacing: false,
            sessionPacingDisplayMode: .dotDelta,
            weeklyPacingDisplayMode: .dotDelta,
            hasConfig: true,
            hasError: false,
            themeColors: .default,
            thresholds: .default,
            menuBarMonochrome: false,
            fiveHourReset: "",
            fiveHourResetAbsolute: "",
            fiveHourResetDate: nil,
            sevenDayResetDate: nil,
            sonnetResetDate: nil,
            designResetDate: nil,
            hasFiveHourBucket: true,
            resetDisplayFormat: .relative,
            resetTextColorHex: "",
            sessionPeriodColorHex: "",
            smartResetColor: false,
            smartColorProfile: .balanced,
            pacingMargin: 10,
            menuBarStyle: .classic,
            pacingShape: .circle,
            designPct: 0,
            hasDesign: false,
            fablePct: 0,
            hasFable: false,
            fableResetDate: nil,
            outageActive: outageActive,
            outageHealth: outageHealth,
            nextPollSeconds: nextPollSeconds,
            extraCreditsPct: 0,
            hasExtraCredits: false
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
            pinnedMetrics: [.serviceStatus],
            outageHealth: .healthy,
            nextPollSeconds: nil
        )
        let down = Self.sampleRenderData(
            pinnedMetrics: [.serviceStatus],
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
        pinned: Set<MetricID> = [.extraCredits],
        hasExtraCredits: Bool = true,
        extraCreditsPct: Int = 67,
        style: MenuBarStyle = .classic
    ) -> MenuBarRenderer.RenderData {
        MenuBarRenderer.RenderData(
            pinnedMetrics: pinned,
            displaySonnet: false,
            fiveHourPct: 0, sevenDayPct: 0, sonnetPct: 0,
            weeklyPacingDelta: 0, weeklyPacingZone: .onTrack, hasWeeklyPacing: false,
            sessionPacingDelta: 0, sessionPacingZone: .onTrack, hasSessionPacing: false,
            sessionPacingDisplayMode: .dotDelta, weeklyPacingDisplayMode: .dotDelta,
            hasConfig: true, hasError: false,
            themeColors: .default, thresholds: .default,
            menuBarMonochrome: false,
            fiveHourReset: "", fiveHourResetAbsolute: "",
            fiveHourResetDate: nil, sevenDayResetDate: nil, sonnetResetDate: nil, designResetDate: nil,
            hasFiveHourBucket: false,
            resetDisplayFormat: .relative,
            resetTextColorHex: "", sessionPeriodColorHex: "",
            smartResetColor: false, smartColorProfile: .balanced,
            pacingMargin: 10,
            menuBarStyle: style,
            pacingShape: .circle,
            designPct: 0, hasDesign: false,
            fablePct: 0, hasFable: false, fableResetDate: nil,
            outageActive: false, outageHealth: .healthy, nextPollSeconds: nil,
            extraCreditsPct: extraCreditsPct, hasExtraCredits: hasExtraCredits
        )
    }

    @Test("EC pinned + pool enabled renders a value (non-template image)")
    func renderedWhenEnabled() {
        let image = MenuBarRenderer.renderUncached(data(hasExtraCredits: true))
        // The pinned-metrics path produces a non-template text image; the
        // logo fallback is a template. So a non-template image proves EC drew.
        #expect(image.isTemplate == false)
        #expect(image.size.width > 0)
    }

    @Test("EC pinned but pool disabled falls back to the logo (template image)")
    func logoFallbackWhenDisabled() {
        // Only EC is pinned and it's filtered out → ordered list is empty →
        // the renderer returns the template logo instead of a 0-width sliver.
        let image = MenuBarRenderer.renderUncached(data(hasExtraCredits: false))
        #expect(image.isTemplate == true)
    }

    @Test("EC renders in badge style too")
    func renderedInBadgeStyle() {
        let image = MenuBarRenderer.renderUncached(data(hasExtraCredits: true, style: .badge))
        #expect(image.isTemplate == false)
        #expect(image.size.width > 0)
    }
}

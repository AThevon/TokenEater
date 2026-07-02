import Testing
import Foundation
import SwiftUI

@Suite("GaugeColorResolver")
struct GaugeColorResolverTests {

    private var theme: ThemeColors { ThemeColors.preset(for: "default") ?? ThemeColors.allPresets[0].colors }
    private var thresholds: UsageThresholds { .default }

    // MARK: - mode decision

    @Test func smartEnabledWithWindowSelectsSmart() {
        // A positive window keeps smart even for metrics without a reset date
        // (e.g. Opus/Cowork): the smart path handles the missing reset internally.
        #expect(GaugeColorResolver.mode(smartColorEnabled: true, windowDuration: 5 * 3600) == .smart)
    }

    @Test func smartDisabledSelectsThreshold() {
        #expect(GaugeColorResolver.mode(smartColorEnabled: false, windowDuration: 5 * 3600) == .threshold)
    }

    @Test func smartEnabledButNoWindowSelectsThreshold() {
        // e.g. the Extra Credits pool has no window (windowDuration 0) -> threshold ladder.
        #expect(GaugeColorResolver.mode(smartColorEnabled: true, windowDuration: 0) == .threshold)
    }

    // MARK: - threshold mode equals the static ramp and ignores time inputs

    @Test func thresholdColorMatchesStaticRamp() {
        let resolved = GaugeColorResolver.color(
            mode: .threshold,
            utilization: 95,
            resetDate: Date().addingTimeInterval(3600),
            windowDuration: 5 * 3600,
            theme: theme,
            thresholds: thresholds,
            pacingMargin: 10,
            profile: .default
        )
        let direct = theme.gaugeColor(for: 95, thresholds: thresholds)
        #expect(resolved == direct)
    }

    @Test func thresholdColorIgnoresResetDate() {
        let withReset = GaugeColorResolver.color(
            mode: .threshold,
            utilization: 50,
            resetDate: Date().addingTimeInterval(60),
            windowDuration: 5 * 3600,
            theme: theme,
            thresholds: thresholds,
            pacingMargin: 10,
            profile: .default
        )
        let withoutReset = GaugeColorResolver.color(
            mode: .threshold,
            utilization: 50,
            resetDate: nil,
            windowDuration: 5 * 3600,
            theme: theme,
            thresholds: thresholds,
            pacingMargin: 10,
            profile: .default
        )
        #expect(withReset == withoutReset)
    }

    // MARK: - smart mode matches ThemeColors.smartGaugeColor for the same inputs

    @Test func smartColorMatchesThemeSmartGauge() {
        let now = Date()
        let reset = now.addingTimeInterval(2 * 3600)
        let resolved = GaugeColorResolver.color(
            mode: .smart,
            utilization: 80,
            resetDate: reset,
            windowDuration: 5 * 3600,
            theme: theme,
            thresholds: thresholds,
            pacingMargin: 10,
            now: now,
            profile: .default
        )
        let direct = theme.smartGaugeColor(
            utilization: 80,
            resetDate: reset,
            windowDuration: 5 * 3600,
            thresholds: thresholds,
            pacingMargin: 10,
            now: now,
            profile: .default
        )
        #expect(resolved == direct)
    }
}

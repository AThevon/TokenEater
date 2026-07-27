import Foundation

@MainActor
extension MenuBarRenderer.RenderData {
    /// Builds render data from the live stores. Shared by the status bar
    /// (`StatusBarController`) and the menu bar editor's live preview, so both
    /// render the exact same pixels for the current composition.
    static func live(
        usage: UsageStore,
        theme: ThemeStore,
        settings: SettingsStore,
        vendor: VendorStatusStore
    ) -> MenuBarRenderer.RenderData {
        MenuBarRenderer.RenderData(
            composition: settings.menuBarComposition,
            fiveHourPct: usage.fiveHourPct,
            sevenDayPct: usage.sevenDayPct,
            sonnetPct: usage.sonnetPct,
            weeklyPacingDelta: Int(usage.pacingResult?.delta ?? 0),
            weeklyPacingZone: usage.pacingResult?.zone ?? .onTrack,
            hasWeeklyPacing: usage.pacingResult != nil,
            sessionPacingDelta: Int(usage.fiveHourPacing?.delta ?? 0),
            sessionPacingZone: usage.fiveHourPacing?.zone ?? .onTrack,
            hasSessionPacing: usage.fiveHourPacing != nil,
            hasConfig: usage.hasConfig,
            hasError: usage.hasError,
            isAwaitingRefresh: usage.isAwaitingRefresh,
            themeColors: theme.current,
            thresholds: theme.thresholds,
            menuBarMonochrome: theme.menuBarMonochrome,
            fiveHourReset: usage.fiveHourReset,
            fiveHourResetAbsolute: usage.fiveHourResetAbsolute,
            fiveHourResetDate: usage.lastUsage?.fiveHour?.resetsAtDate,
            sevenDayResetDate: usage.lastUsage?.sevenDay?.resetsAtDate,
            sonnetResetDate: usage.lastUsage?.sevenDaySonnet?.resetsAtDate,
            designResetDate: usage.lastUsage?.sevenDayDesign?.resetsAtDate,
            hasFiveHourBucket: usage.lastUsage?.fiveHour != nil,
            resetTextColorHex: settings.resetTextColorHex,
            sessionPeriodColorHex: settings.sessionPeriodColorHex,
            smartResetColor: settings.smartColorEnabled,
            smartColorProfile: settings.smartColorProfile,
            pacingMargin: Double(settings.pacingMargin),
            designPct: usage.designPct,
            hasDesign: usage.hasDesign,
            fablePct: usage.fablePct,
            hasFable: usage.hasFable,
            fableResetDate: usage.lastUsage?.sevenDayFable?.resetsAtDate,
            outageActive: settings.statusShowMenuBarBadge && vendor.isDegraded,
            outageHealth: vendor.worstHealth,
            nextPollSeconds: vendor.nextPollDate.map { max(0, Int(ceil($0.timeIntervalSinceNow))) },
            extraCreditsPct: usage.extraCreditsPct,
            hasExtraCredits: usage.hasExtraCredits
        )
    }
}

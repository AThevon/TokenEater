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
        vendor: VendorStatusStore,
        codex: CodexUsageStore,
        accounts: AccountsStore? = nil
    ) -> MenuBarRenderer.RenderData {
        /// A window the plan does not have, or a provider that is switched
        /// off, resolves to nil and its segments disappear from the bar.
        func codexSegment(_ wanted: CodexWindowKind) -> MenuBarRenderer.CodexSegmentData? {
            guard codex.isEnabled, let window = codex.windows.first(where: { $0.kind == wanted }) else { return nil }
            return MenuBarRenderer.CodexSegmentData(
                pct: window.pct,
                resetDate: window.resetDate,
                windowDuration: window.windowDuration,
                hasPacing: window.pacing != nil,
                pacingZone: window.pacing?.zone ?? .onTrack,
                pacingDelta: Int(window.pacing?.delta ?? 0)
            )
        }

        var data = MenuBarRenderer.RenderData(
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
            fablePacingDelta: Int(usage.fablePacing?.delta ?? 0),
            fablePacingZone: usage.fablePacing?.zone ?? .onTrack,
            hasFablePacing: usage.fablePacing != nil,
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
            hasFiveHourBucket: usage.lastUsage?.fiveHour != nil,
            resetTextColorHex: settings.resetTextColorHex,
            sessionPeriodColorHex: settings.sessionPeriodColorHex,
            smartResetColor: settings.smartColorEnabled,
            smartColorProfile: settings.smartColorProfile,
            pacingMargin: Double(settings.pacingMargin),
            fablePct: usage.fablePct,
            hasFable: usage.hasFable,
            fableResetDate: usage.lastUsage?.sevenDayFable?.resetsAtDate,
            outageActive: settings.statusShowMenuBarBadge && vendor.isDegraded,
            outageHealth: vendor.worstHealth,
            nextPollSeconds: vendor.nextPollDate.map { max(0, Int(ceil($0.timeIntervalSinceNow))) },
            extraCreditsPct: usage.extraCreditsPct,
            hasExtraCredits: usage.hasExtraCredits,
            extraCreditsUncappedSpend: usage.extraCreditsUncappedSpend,
            extraCreditsUncappedHasSpend: usage.extraCreditsUncappedHasSpend,
            codexSession: codexSegment(.session),
            codexWeekly: codexSegment(.weekly),
            visibleProviders: Set(settings.activeProviders.filter { settings.activeProviderMode.shows($0) })
        )
        // Each running added account, built the same way from its own store,
        // for the segments pinned to it. Paused accounts are left out, so
        // their segments step aside.
        if let accounts, settings.claudeEnabled {
            for id in accounts.activeAccountIDs where !id.isMain {
                guard let store = accounts.usageStore(for: id) else { continue }
                data.accountData[id.rawValue] = .live(
                    usage: store, theme: theme, settings: settings, vendor: vendor, codex: codex
                )
            }
        }
        return data
    }

    /// The bar as it will look once a just-connected account is added: the
    /// All layout with the account's segments, which show "--" until its
    /// first refresh. Drawn in the add-account sheet; nothing is saved.
    static func previewAddingAccount(
        _ id: AccountID,
        usage: UsageStore,
        theme: ThemeStore,
        settings: SettingsStore,
        vendor: VendorStatusStore,
        codex: CodexUsageStore,
        accounts: AccountsStore
    ) -> (before: MenuBarRenderer.RenderData, after: MenuBarRenderer.RenderData) {
        var before = live(usage: usage, theme: theme, settings: settings, vendor: vendor, codex: codex, accounts: accounts)
        let allLayout = settings.allModeMenuBarComposition
        before.composition = allLayout
        before.visibleProviders = Set(settings.activeProviders)
        var pending = before
        pending.accountData = [:]
        pending.showsPlaceholderValues = true
        var after = before
        after.composition = allLayout.addingAccountSegments(id)
        after.accountData[id.rawValue] = pending
        return (before, after)
    }
}

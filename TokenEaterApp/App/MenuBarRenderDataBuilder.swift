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
        data.hasNumbers = usage.lastUsage != nil
        // Each running added account, built the same way from its own store,
        // for the segments that resolve to it. Paused accounts are left out,
        // so their segments step aside.
        if let accounts, settings.claudeEnabled {
            for id in accounts.activeAccountIDs where !id.isMain {
                guard let store = accounts.usageStore(for: id) else { continue }
                data.accountData[id.rawValue] = .live(
                    usage: store, theme: theme, settings: settings, vendor: vendor, codex: codex
                )
            }
            // Claude mode shows the focused account: its segments carry no
            // account of their own and read that one.
            let focused = settings.focusedClaudeAccount
            if settings.activeProviderMode == .claude, !focused.isMain, data.accountData[focused.rawValue] != nil {
                data.defaultAccount = focused.rawValue
            }
            if accounts.showsAccountMarkers {
                data.accountMarkers = markers(for: accounts.activeAccountIDs, accounts: accounts)
                data.marksLoneAccount = settings.activeProviderMode == .claude
            }
        }
        return data
    }

    /// The marker of each running account, the main one included.
    private static func markers(
        for ids: [AccountID],
        accounts: AccountsStore
    ) -> [String: MenuBarRenderer.AccountMarker] {
        var markers: [String: MenuBarRenderer.AccountMarker] = [:]
        for id in ids {
            guard let record = accounts.record(for: id) else { continue }
            markers[id.rawValue] = MenuBarRenderer.AccountMarker(label: record.name, colorHex: record.colorHex)
        }
        return markers
    }

    /// The bar as it will look once a just-connected account is added: the
    /// All layout with the account's segments, which show "--" until its
    /// first refresh, every run marked with its account since there will be
    /// two. `name` and `colorHex` are the new account's as the sheet has them;
    /// `mainName` is the main account's when the sheet is renaming it too
    /// (the bar shows only colours, but a monochrome one draws initials).
    /// Drawn in the add-account sheet; nothing is saved.
    static func previewAddingAccount(
        _ id: AccountID,
        name: String,
        colorHex: String,
        mainName: String? = nil,
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
        before.defaultAccount = AccountID.main.rawValue
        var pending = before
        pending.accountData = [:]
        pending.accountMarkers = [:]
        pending.showsPlaceholderValues = true
        var after = before
        after.composition = allLayout.addingAccountSegments(id)
        after.accountData[id.rawValue] = pending
        var markers = markers(for: accounts.activeAccountIDs, accounts: accounts)
        if let mainName, let main = markers[AccountID.main.rawValue] {
            markers[AccountID.main.rawValue] = MenuBarRenderer.AccountMarker(
                label: AccountNameRules.sanitize(mainName, fallback: main.label),
                colorHex: main.colorHex
            )
        }
        markers[id.rawValue] = MenuBarRenderer.AccountMarker(label: name, colorHex: colorHex)
        after.accountMarkers = markers
        return (before, after)
    }
}

import SwiftUI

/// Shown once when the minor version changes, in the dashboard window, in the
/// slot the wizard uses on a fresh install. Settings > General replays it.
///
/// This is the 6.1 screen, and like the 6.0 one it teaches with the app's own
/// pieces rather than pictures of them: the first pane draws a sample menu
/// bar through the real `MenuBarRenderer` and two sample dashboard columns
/// with the real `DashboardColumnHeader` and `ProviderHeroFace`, the second
/// hosts the live Claude card from Settings > Providers, where an account is
/// actually added. The sample accounts are made up; nothing on this screen
/// reads a credential or writes a setting until the user acts on that card.
struct WhatsNewView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pane = 0
    private let panes = 3

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            brandBar

            // The setup step carries the live Claude card, which grows with
            // every account and can outgrow a short window. Scrolls only when
            // it has to, so the usual case still reads as a fixed pane.
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch pane {
                    case 0: accountsPane
                    case 1: setupPane
                    default: reliabilityPane
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .padding(.top, DS.Spacing.lg)

            // A fixed gap under the header with the footer pinned, rather than
            // centring: the panes are different heights, and centring made
            // the title jump vertically on every Next.
            Spacer(minLength: DS.Spacing.lg)

            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 18)
        // One measure for everything: the subtitle stays near 65 characters
        // and the rows stop stretching their two ends apart.
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chrome

    private var brandBar: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("TokenEater \(SettingsStore.currentVersion)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer()
            Button(action: finish) {
                Text("whatsNew.skip")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Spacing.sm) {
            HStack(spacing: 6) {
                ForEach(0..<panes, id: \.self) { index in
                    Capsule()
                        .fill(index == pane ? DS.Palette.textPrimary.opacity(0.8) : Color.white.opacity(0.16))
                        .frame(width: index == pane ? 16 : 6, height: 6)
                        .animation(reduceMotion ? nil : DS.Motion.springSnap, value: pane)
                }
            }
            Spacer()
            if pane > 0 {
                secondaryButton("whatsNew.back") { pane -= 1 }
            }
            primaryButton(pane == panes - 1 ? "whatsNew.done" : "whatsNew.next") {
                if pane == panes - 1 { finish() } else { pane += 1 }
            }
        }
    }

    // MARK: - Panes

    /// Several accounts, shown the way they look: one menu bar with each
    /// account's run of numbers behind its marker, and the dashboard's two
    /// columns under their headers. Everything below the title is drawn by
    /// the components the app itself uses, fed with two sample accounts.
    private var accountsPane: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            title("whatsNew.accounts.title", "whatsNew.accounts.body")

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                menuBarSample
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    ForEach(WhatsNewSample.accounts) { account in
                        dashboardColumn(account)
                    }
                }
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panel)
            // A new identity per visit replays the rings filling up, which
            // is what makes the two columns read as two live accounts.
            .id(pane)

            VStack(alignment: .leading, spacing: 7) {
                featureRow("menubar.rectangle", "whatsNew.accounts.menuBar.title", "whatsNew.accounts.menuBar.text")
                featureRow("rectangle.split.2x1", "whatsNew.accounts.surfaces.title", "whatsNew.accounts.surfaces.text")
                featureRow("bell", "whatsNew.accounts.alerts.title", "whatsNew.accounts.alerts.text")
                featureRow("square.grid.2x2", "whatsNew.accounts.widget.title", "whatsNew.accounts.widget.text")
                featureRow("clock.arrow.circlepath", "whatsNew.accounts.history.title", "whatsNew.accounts.history.text")
            }
        }
    }

    /// Where an account is added and where the main one changes folder, live:
    /// the same Claude card as Settings > Providers, Codex's left out.
    private var setupPane: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            title("whatsNew.setup.title", "whatsNew.setup.body")

            VStack(alignment: .leading, spacing: 6) {
                Text("whatsNew.setup.main.title")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("whatsNew.setup.main.body")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, DS.Spacing.xxs)

            ProvidersSectionProviders(showsCodex: false)

            Text("whatsNew.setup.hint")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The two login fixes up front, then the rest in one short list, then
    /// the people behind them.
    private var reliabilityPane: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            title("whatsNew.login.title", "whatsNew.login.body")

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                highlightRow("key", "whatsNew.login.keychain.title", "whatsNew.login.keychain.text")
                highlightRow("clock.badge.exclamationmark", "whatsNew.login.expired.title", "whatsNew.login.expired.text")
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panel)

            VStack(alignment: .leading, spacing: 7) {
                Text("whatsNew.more.title")
                    .textCase(.uppercase)
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .padding(.bottom, 2)
                bullet("whatsNew.more.studio")
                bullet("whatsNew.more.history")
                bullet("whatsNew.more.codexPlans")
                bullet("whatsNew.more.extraCredits")
                bullet("whatsNew.more.decoding")
            }
            .padding(.top, DS.Spacing.xs)

            Text("whatsNew.thanks")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Spacing.xxs)
        }
    }

    // MARK: - Samples

    /// The menu bar the two sample accounts would get from the classic
    /// layout, drawn by the renderer the status item uses, with the user's
    /// own theme and Smart Color settings.
    private var menuBarSample: some View {
        let image = MenuBarRenderer.renderWithHitRects(
            WhatsNewSample.menuBar(theme: themeStore, settings: settingsStore)
        ).image
        let scale: CGFloat = 1.5
        return HStack {
            Spacer(minLength: 0)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: image.size.width * scale, height: image.size.height * scale)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(hex: "#1E1E1E"))
        )
        .accessibilityHidden(true)
    }

    /// One account's dashboard column: its header, then its glance card at
    /// a reduced scale. The face is laid out at a width it is designed for
    /// and scaled down whole, so nothing in it truncates or rewraps.
    private func dashboardColumn(_ account: WhatsNewSample.Account) -> some View {
        let faceSize = CGSize(width: 360, height: 190)
        let scale: CGFloat = 0.7
        let window = MonitoringView.ClaudeHeroWindow.session
        let resetDate = Date().addingTimeInterval(account.sessionResetIn)
        let mode = GaugeColorResolver.mode(
            smartColorEnabled: settingsStore.smartColorEnabled,
            windowDuration: window.duration
        )
        let color = GaugeColorResolver.color(
            mode: mode,
            utilization: account.sessionPct,
            resetDate: resetDate,
            windowDuration: window.duration,
            theme: themeStore.current,
            thresholds: themeStore.thresholds,
            pacingMargin: Double(settingsStore.pacingMargin),
            profile: settingsStore.smartColorProfile
        )
        let gradient = GaugeColorResolver.gradient(
            mode: mode,
            utilization: account.sessionPct,
            resetDate: resetDate,
            windowDuration: window.duration,
            theme: themeStore.current,
            thresholds: themeStore.thresholds,
            pacingMargin: Double(settingsStore.pacingMargin),
            profile: settingsStore.smartColorProfile,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DashboardColumnHeader(accountName: account.name, colorHex: account.colorHex)
            ProviderHeroFace(
                provider: .claude,
                windowLabel: window.localizedLabel,
                pct: account.sessionPct,
                gaugeColor: color,
                gaugeGradient: gradient,
                zone: account.sessionZone,
                resetText: ResetCountdownFormatter.session(from: resetDate).relative,
                resetDate: resetDate,
                name: account.name
            )
            .padding(DS.Spacing.lg)
            .frame(width: faceSize.width, height: faceSize.height)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.cardLg)
                    .fill(DS.Palette.bgElevated.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.cardLg)
                            .stroke(color.opacity(0.18), lineWidth: 1)
                    )
            )
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: faceSize.width * scale, height: faceSize.height * scale, alignment: .topLeading)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pieces

    private var panel: some View {
        RoundedRectangle(cornerRadius: DS.Radius.card)
            .fill(DS.Palette.bgElevated.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
            )
    }

    private func title(_ heading: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(DS.Typography.title1)
                .foregroundStyle(DS.Palette.textPrimary)
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One line per surface: what it now does with several accounts.
    private func featureRow(_ icon: String, _ heading: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(width: 18)
            (Text(heading).fontWeight(.semibold).foregroundColor(DS.Palette.textPrimary)
                + Text(verbatim: "  ")
                + Text(text).foregroundColor(DS.Palette.textSecondary))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func highlightRow(_ icon: String, _ heading: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(heading)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
            Circle()
                .fill(DS.Palette.textTertiary)
                .frame(width: 4, height: 4)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func primaryButton(_ key: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.bgElevated)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(DS.Palette.textPrimary.opacity(0.92)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }

    private func secondaryButton(_ key: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func finish() {
        settingsStore.markWhatsNewSeen()
    }
}

// MARK: - Sample accounts

/// Two made-up accounts for the first pane. Values only: no record, no store,
/// no file, so the preview can never be mistaken for, or leak into, the
/// user's own accounts.
@MainActor
enum WhatsNewSample {
    struct Account: Identifiable {
        let id: AccountID
        let name: String
        let colorHex: String
        let sessionPct: Int
        let sessionZone: PacingZone
        /// From now, so the countdowns read like a live bar.
        let sessionResetIn: TimeInterval
        let weeklyPct: Int
        let weeklyZone: PacingZone
        let weeklyResetIn: TimeInterval
    }

    static var accounts: [Account] {
        [
            Account(
                id: .main,
                name: String(localized: "whatsNew.sample.main"),
                colorHex: AccountPalette.presets[0],
                sessionPct: 42,
                sessionZone: .onTrack,
                sessionResetIn: 2 * 3600 + 14 * 60,
                weeklyPct: 61,
                weeklyZone: .onTrack,
                weeklyResetIn: 3 * 86_400 + 5 * 3600
            ),
            Account(
                id: AccountID(rawValue: "acct-whatsnew-sample"),
                name: String(localized: "whatsNew.sample.work"),
                colorHex: AccountPalette.presets[1],
                sessionPct: 78,
                sessionZone: .warning,
                sessionResetIn: 47 * 60,
                weeklyPct: 35,
                weeklyZone: .chill,
                weeklyResetIn: 5 * 86_400 + 2 * 3600
            ),
        ]
    }

    /// The classic layout with the second account's segments added the way
    /// the add-account sheet adds them, both runs marked with their account.
    static func menuBar(theme: ThemeStore, settings: SettingsStore) -> MenuBarRenderer.RenderData {
        let samples = accounts
        let main = samples[0]
        let added = samples[1]
        var data = renderData(
            for: main,
            composition: MenuBarComposition.default.addingAccountSegments(added.id),
            theme: theme,
            settings: settings
        )
        data.accountData[added.id.rawValue] = renderData(
            for: added, composition: data.composition, theme: theme, settings: settings
        )
        var markers: [String: MenuBarRenderer.AccountMarker] = [:]
        for account in samples {
            markers[account.id.rawValue] = MenuBarRenderer.AccountMarker(label: account.name, colorHex: account.colorHex)
        }
        data.accountMarkers = markers
        return data
    }

    private static func renderData(
        for account: Account,
        composition: MenuBarComposition,
        theme: ThemeStore,
        settings: SettingsStore
    ) -> MenuBarRenderer.RenderData {
        let now = Date()
        let sessionReset = now.addingTimeInterval(account.sessionResetIn)
        let weeklyReset = now.addingTimeInterval(account.weeklyResetIn)
        let session = ResetCountdownFormatter.session(from: sessionReset, now: now)
        return MenuBarRenderer.RenderData(
            composition: composition,
            fiveHourPct: account.sessionPct,
            sevenDayPct: account.weeklyPct,
            sonnetPct: 0,
            weeklyPacingDelta: 0,
            weeklyPacingZone: account.weeklyZone,
            hasWeeklyPacing: true,
            sessionPacingDelta: 0,
            sessionPacingZone: account.sessionZone,
            hasSessionPacing: true,
            fablePacingDelta: 0,
            fablePacingZone: .onTrack,
            hasFablePacing: false,
            hasConfig: true,
            hasError: false,
            isAwaitingRefresh: false,
            themeColors: theme.current,
            thresholds: theme.thresholds,
            menuBarMonochrome: theme.menuBarMonochrome,
            fiveHourReset: session.relative,
            fiveHourResetAbsolute: session.absolute,
            fiveHourResetDate: sessionReset,
            sevenDayResetDate: weeklyReset,
            sonnetResetDate: nil,
            hasFiveHourBucket: true,
            resetTextColorHex: settings.resetTextColorHex,
            sessionPeriodColorHex: settings.sessionPeriodColorHex,
            smartResetColor: settings.smartColorEnabled,
            smartColorProfile: settings.smartColorProfile,
            pacingMargin: Double(settings.pacingMargin),
            fablePct: 0,
            hasFable: false,
            fableResetDate: nil,
            outageActive: false,
            outageHealth: .healthy,
            nextPollSeconds: nil,
            extraCreditsPct: 0,
            hasExtraCredits: false,
            extraCreditsUncappedSpend: nil,
            extraCreditsUncappedHasSpend: false,
            codexSession: nil,
            codexWeekly: nil,
            visibleProviders: [.claude]
        )
    }
}

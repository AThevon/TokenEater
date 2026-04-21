import SwiftUI

/// Focus layout - a single hero piece (picked via `focusHero` radio),
/// auto-rendered satellites, plus middle mini-paces / watchers / timestamp.
/// The hero reflects what the user wants to watch "first": time left, or a
/// raw percentage.
struct FocusLayoutView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader()

            if usageStore.hasError {
                PopoverErrorBanner()
            }

            heroBlock
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            satellitesRow
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            extraSatellitesRow

            middleZone
        }
        .frame(width: 300)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)))
    }

    private var layout: VariantLayout { settingsStore.popoverConfig.focus }
    private var hero: FocusHeroChoice { settingsStore.popoverConfig.focusHero }

    // MARK: - Hero

    @ViewBuilder
    private var heroBlock: some View {
        FocusHeroView(hero: hero)
    }

    // MARK: - Satellites

    @ViewBuilder
    private var satellitesRow: some View {
        let sats = FocusHeroChoice.satellites(for: hero)
        HStack(spacing: 8) {
            ForEach(sats, id: \.self) { s in
                FocusSatelliteCard(value: s)
            }
        }
    }

    // MARK: - Extra satellites (Sonnet / Design)

    @ViewBuilder
    private var extraSatellitesRow: some View {
        let showSonnet = settingsStore.displaySonnet
        let showDesign = settingsStore.displayDesign && usageStore.hasDesign
        if showSonnet || showDesign {
            HStack(spacing: 8) {
                if showSonnet {
                    CompactExtraChip(
                        label: String(localized: "metric.sonnet"),
                        pct: usageStore.sonnetPct,
                        theme: themeStore
                    )
                }
                if showDesign {
                    CompactExtraChip(
                        label: String(localized: "metric.design"),
                        pct: usageStore.designPct,
                        theme: themeStore
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Middle (mini pace + watchers + timestamp)

    @ViewBuilder
    private var middleZone: some View {
        let visibleMiddle = layout.middle.filter { !$0.hidden }
        if visibleMiddle.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                ForEach(visibleMiddle) { state in
                    middleBlock(for: state.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func middleBlock(for id: PopoverBlockID) -> some View {
        switch id {
        case .sessionPaceMini:
            if let pacing = usageStore.fiveHourPacing {
                MiniPaceRow(
                    label: String(localized: "pacing.session.label.short"),
                    pacing: pacing,
                    theme: themeStore
                )
            }
        case .weeklyPaceMini:
            if let pacing = usageStore.pacingResult {
                MiniPaceRow(
                    label: String(localized: "pacing.weekly.label.short"),
                    pacing: pacing,
                    theme: themeStore
                )
            }
        case .watchers:
            PopoverWatchersToggle()
        case .timestamp:
            PopoverTimestamp()
        case .openTokenEaterButton:
            PopoverOpenButton()
        case .quitButton:
            PopoverQuitButton()
        default:
            EmptyView()
        }
    }
}

// MARK: - Hero view (big arc + value)

private struct FocusHeroView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore

    let hero: FocusHeroChoice

    var body: some View {
        ZStack {
            heroArc
            VStack(spacing: 4) {
                Text(heroValue)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(heroColor)
                    .shadow(color: heroColor.opacity(0.35), radius: 10)
                Text(heroLabel.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1)
            }
        }
        .frame(height: 150)
    }

    private var heroValue: String {
        switch hero {
        case .sessionReset:
            return usageStore.fiveHourReset.isEmpty ? "-" : usageStore.fiveHourReset
        case .weeklyReset:
            return usageStore.sevenDayReset.isEmpty ? "-" : usageStore.sevenDayReset
        case .sessionValue: return "\(usageStore.fiveHourPct)%"
        case .weeklyValue:  return "\(usageStore.sevenDayPct)%"
        }
    }

    private var heroLabel: String {
        switch hero {
        case .sessionReset: return String(localized: "focus.hero.sessionReset")
        case .weeklyReset:  return String(localized: "focus.hero.weeklyReset")
        case .sessionValue: return String(localized: "focus.hero.sessionValue")
        case .weeklyValue:  return String(localized: "focus.hero.weeklyValue")
        }
    }

    private var heroColor: Color {
        switch hero {
        case .sessionReset, .weeklyReset:
            return Color(red: 0.99, green: 0.90, blue: 0.54)
        case .sessionValue:
            return PopoverColors.gauge(pct: usageStore.fiveHourPct, theme: themeStore)
        case .weeklyValue:
            return PopoverColors.gauge(pct: usageStore.sevenDayPct, theme: themeStore)
        }
    }

    private var heroProgress: Double {
        switch hero {
        case .sessionReset:
            return resetProgress(from: usageStore.lastUsage?.fiveHour?.resetsAtDate, window: 5 * 3600)
        case .weeklyReset:
            return resetProgress(from: usageStore.lastUsage?.sevenDay?.resetsAtDate, window: 7 * 86_400)
        case .sessionValue:
            return Double(min(max(usageStore.fiveHourPct, 0), 100)) / 100.0
        case .weeklyValue:
            return Double(min(max(usageStore.sevenDayPct, 0), 100)) / 100.0
        }
    }

    private func resetProgress(from date: Date?, window: TimeInterval) -> Double {
        guard let date else { return 0 }
        let remaining = max(date.timeIntervalSinceNow, 0)
        let elapsed = max(window - remaining, 0)
        return min(elapsed / window, 1)
    }

    /// Open arc drawn from bottom-left to bottom-right of the hero block.
    private var heroArc: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let strokeW: CGFloat = 8
            let inset: CGFloat = strokeW / 2 + 4
            let rect = CGRect(x: inset, y: inset, width: w - inset * 2, height: (h - inset) * 2)
            let path = Path { p in
                p.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2,
                    startAngle: .degrees(180),
                    endAngle: .degrees(360),
                    clockwise: false
                )
            }
            ZStack {
                path
                    .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                path
                    .trim(from: 0, to: heroProgress)
                    .stroke(heroColor, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                    .shadow(color: heroColor.opacity(0.5), radius: 8)
            }
        }
    }
}

// MARK: - Satellite card (2 of these render below the hero)

private struct FocusSatelliteCard: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore

    let value: FocusHeroChoice

    var body: some View {
        VStack(spacing: 4) {
            Text(displayValue)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }

    private var displayValue: String {
        switch value {
        case .sessionReset: return usageStore.fiveHourReset.isEmpty ? "-" : usageStore.fiveHourReset
        case .weeklyReset:  return usageStore.sevenDayReset.isEmpty ? "-" : usageStore.sevenDayReset
        case .sessionValue: return "\(usageStore.fiveHourPct)%"
        case .weeklyValue:  return "\(usageStore.sevenDayPct)%"
        }
    }

    private var label: String {
        switch value {
        case .sessionReset: return String(localized: "focus.sat.sessionReset")
        case .weeklyReset:  return String(localized: "focus.sat.weeklyReset")
        case .sessionValue: return String(localized: "focus.sat.sessionValue")
        case .weeklyValue:  return String(localized: "focus.sat.weeklyValue")
        }
    }

    private var color: Color {
        switch value {
        case .sessionReset, .weeklyReset:
            return Color(red: 0.99, green: 0.90, blue: 0.54)
        case .sessionValue:
            return PopoverColors.gauge(pct: usageStore.fiveHourPct, theme: themeStore)
        case .weeklyValue:
            return PopoverColors.gauge(pct: usageStore.sevenDayPct, theme: themeStore)
        }
    }
}

// MARK: - Mini pace row

private struct MiniPaceRow: View {
    let label: String
    let pacing: PacingResult
    let theme: ThemeStore

    var body: some View {
        let color = PopoverColors.zone(pacing.zone, theme: theme)
        let sign = pacing.delta >= 0 ? "+" : ""
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text("\(sign)\(Int(pacing.delta))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
                )
        )
    }
}

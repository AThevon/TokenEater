import SwiftUI

/// Compact ticker layout - two chips for Session + Weekly (mini rings +
/// values + subtitles), a grid of pace tiles, watchers, and a timestamp.
/// Everything except the footer lives in `compact.middle` so the user can
/// reorder freely and hide what they don't need.
struct CompactLayoutView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader()

            if usageStore.hasError {
                PopoverErrorBanner()
            }

            extraSatellitesRow
            middleZone
        }
        .frame(width: 300)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)))
    }

    /// Sonnet / Design mini-chips rendered just under the header when the
    /// user opted into them. Independent of the middle drag list so we
    /// don't have to introduce new BlockIDs for these.
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
                        resetDate: usageStore.lastUsage?.sevenDaySonnet?.resetsAtDate,
                        windowDuration: 7 * 86_400,
                        theme: themeStore,
                        settings: settingsStore
                    )
                }
                if showDesign {
                    CompactExtraChip(
                        label: String(localized: "metric.design"),
                        pct: usageStore.designPct,
                        resetDate: usageStore.lastUsage?.sevenDayDesign?.resetsAtDate,
                        windowDuration: 7 * 86_400,
                        theme: themeStore,
                        settings: settingsStore
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }

    private var layout: VariantLayout { settingsStore.popoverConfig.compact }

    // MARK: - Middle

    @ViewBuilder
    private var middleZone: some View {
        let visibleMiddle = layout.middle.filter { !$0.hidden }
        if visibleMiddle.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 10) {
                // Chips + pace tiles naturally pair up in 2-column grids.
                // The renderer below groups consecutive same-type blocks so
                // the layout stays dense.
                ForEach(groupedMiddle(visibleMiddle), id: \.self) { group in
                    switch group {
                    case .chipPair(let a, let b):
                        HStack(spacing: 8) {
                            chip(for: a)
                            chip(for: b)
                        }
                    case .singleChip(let id):
                        chip(for: id)
                    case .paceTilePair(let a, let b):
                        HStack(spacing: 8) {
                            paceTile(for: a)
                            paceTile(for: b)
                        }
                    case .singlePaceTile(let id):
                        paceTile(for: id)
                    case .watchers:
                        PopoverWatchersToggle()
                    case .timestamp:
                        PopoverTimestamp()
                    case .openButton:
                        PopoverOpenButton()
                    case .quitButton:
                        PopoverQuitButton()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Block grouping

    private enum MiddleGroup: Hashable {
        case chipPair(PopoverBlockID, PopoverBlockID)
        case singleChip(PopoverBlockID)
        case paceTilePair(PopoverBlockID, PopoverBlockID)
        case singlePaceTile(PopoverBlockID)
        case watchers
        case timestamp
        case openButton
        case quitButton
    }

    /// Collapses consecutive chips / tiles into 2-column pairs so the layout
    /// stays dense. Any single leftover (e.g. user hid one chip) is rendered
    /// as a full-width row.
    private func groupedMiddle(_ states: [BlockState]) -> [MiddleGroup] {
        var out: [MiddleGroup] = []
        var i = 0
        let ids = states.map { $0.id }
        while i < ids.count {
            let id = ids[i]
            switch id {
            case .sessionChip, .weeklyChip:
                let next = i + 1 < ids.count ? ids[i + 1] : nil
                if let next, [PopoverBlockID.sessionChip, .weeklyChip].contains(next) {
                    out.append(.chipPair(id, next))
                    i += 2
                } else {
                    out.append(.singleChip(id))
                    i += 1
                }
            case .sessionPaceTile, .weeklyPaceTile:
                let next = i + 1 < ids.count ? ids[i + 1] : nil
                if let next, [PopoverBlockID.sessionPaceTile, .weeklyPaceTile].contains(next) {
                    out.append(.paceTilePair(id, next))
                    i += 2
                } else {
                    out.append(.singlePaceTile(id))
                    i += 1
                }
            case .watchers:
                out.append(.watchers); i += 1
            case .timestamp:
                out.append(.timestamp); i += 1
            case .openTokenEaterButton:
                out.append(.openButton); i += 1
            case .quitButton:
                out.append(.quitButton); i += 1
            default:
                i += 1
            }
        }
        return out
    }

    // MARK: - Block views

    @ViewBuilder
    private func chip(for id: PopoverBlockID) -> some View {
        switch id {
        case .sessionChip:
            ChipView(
                pct: usageStore.fiveHourPct,
                resetDate: usageStore.lastUsage?.fiveHour?.resetsAtDate,
                windowDuration: 5 * 3600,
                label: String(localized: "metric.session"),
                subtitle: sessionChipSubtitle,
                theme: themeStore,
                settings: settingsStore
            )
        case .weeklyChip:
            ChipView(
                pct: usageStore.sevenDayPct,
                resetDate: usageStore.lastUsage?.sevenDay?.resetsAtDate,
                windowDuration: 7 * 86_400,
                label: String(localized: "metric.weekly"),
                subtitle: weeklyChipSubtitle,
                theme: themeStore,
                settings: settingsStore
            )
        default:
            EmptyView()
        }
    }

    private var sessionChipSubtitle: String {
        guard !usageStore.fiveHourReset.isEmpty else { return "" }
        return String(format: String(localized: "compact.chip.sessionLeft"), usageStore.fiveHourReset)
    }

    private var weeklyChipSubtitle: String {
        guard !usageStore.sevenDayReset.isEmpty else { return "" }
        return String(format: String(localized: "compact.chip.weeklyLeft"), usageStore.sevenDayReset)
    }

    @ViewBuilder
    private func paceTile(for id: PopoverBlockID) -> some View {
        switch id {
        case .sessionPaceTile:
            if let pacing = usageStore.fiveHourPacing {
                PaceTileView(
                    label: String(localized: "pacing.session.label.short"),
                    pacing: pacing,
                    theme: themeStore
                )
            }
        case .weeklyPaceTile:
            if let pacing = usageStore.pacingResult {
                PaceTileView(
                    label: String(localized: "pacing.weekly.label.short"),
                    pacing: pacing,
                    theme: themeStore
                )
            }
        default:
            EmptyView()
        }
    }

}

// MARK: - Chip and PaceTile sub-views

private struct ChipView: View {
    let pct: Int
    let resetDate: Date?
    let windowDuration: TimeInterval
    let label: String
    let subtitle: String
    let theme: ThemeStore
    let settings: SettingsStore

    var body: some View {
        let color = PopoverColors.gauge(pct: pct, resetDate: resetDate, windowDuration: windowDuration, theme: theme, settings: settings)
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 4)
                    .frame(width: 38, height: 38)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(pct, 0), 100)) / 100.0)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.4), radius: 3)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(0.5)
                Text("\(pct)%")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(color)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

private struct PaceTileView: View {
    let label: String
    let pacing: PacingResult
    let theme: ThemeStore

    var body: some View {
        let color = PopoverColors.zone(pacing.zone, theme: theme)
        let sign = pacing.delta >= 0 ? "+" : ""
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("\(sign)\(Int(pacing.delta))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            PacingBar(
                actual: pacing.actualUsage,
                expected: pacing.expectedUsage,
                zone: pacing.zone,
                gradient: PopoverColors.zoneGradient(pacing.zone, theme: theme),
                compact: true
            )
        }
        .padding(10)
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

/// Minimal 2-value chip used for Sonnet / Design satellites above the main
/// middle content. Just a mini ring + % + label, no sub-caption.
struct CompactExtraChip: View {
    let label: String
    let pct: Int
    let resetDate: Date?
    let windowDuration: TimeInterval
    let theme: ThemeStore
    let settings: SettingsStore

    var body: some View {
        let color = PopoverColors.gauge(pct: pct, resetDate: resetDate, windowDuration: windowDuration, theme: theme, settings: settings)
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 3)
                    .frame(width: 28, height: 28)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(pct, 0), 100)) / 100.0)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.4), radius: 2)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(0.5)
                Text("\(pct)%")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

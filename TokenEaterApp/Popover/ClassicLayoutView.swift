import SwiftUI

/// Classic popover layout - reproduces the v4.10.x appearance but honours
/// `popoverConfig.classic` so each block can be toggled / reordered.
///
/// Layout flow:
/// - Header (always)
/// - Error banner (if any)
/// - Hero zone: 2 rings. displaySonnet=true keeps the legacy hero+satellites
///   arrangement (Session hero, Weekly + Sonnet satellites). displaySonnet=false
///   renders the two rings as equal size, following `classic.hero` order and
///   visibility.
/// - Middle zone: pacing rows + watchers + timestamp, in the order the user
///   stored. Hidden blocks are skipped.
/// - Footer zone: Open + Quit buttons, in stored order, hidden blocks skipped.
struct ClassicLayoutView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader()

            if usageStore.hasError {
                PopoverErrorBanner()
            }

            heroZone

            middleZone
        }
        .frame(width: 300)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)))
    }

    private var layout: VariantLayout { settingsStore.popoverConfig.classic }

    // MARK: - Hero

    @ViewBuilder
    private var heroZone: some View {
        let sessionVisible = isBlockVisible(.sessionRing)
        let weeklyVisible = isBlockVisible(.weeklyRing)

        if !sessionVisible && !weeklyVisible {
            EmptyView()
        } else if settingsStore.displaySonnet && sessionVisible {
            // Legacy layout: big Session hero + satellites for Weekly / Sonnet.
            PopoverHeroRing()
                .padding(.horizontal, 16)
                .padding(.bottom, 20)

            HStack(spacing: 32) {
                if weeklyVisible {
                    PopoverSatelliteRing(
                        label: String(localized: "metric.weekly"),
                        pct: usageStore.sevenDayPct
                    )
                }
                PopoverSatelliteRing(
                    label: String(localized: "metric.sonnet"),
                    pct: usageStore.sonnetPct
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        } else {
            // Equal rings, following stored hero order + visibility.
            HStack(spacing: 40) {
                ForEach(layout.hero.filter { !$0.hidden }) { state in
                    equalRing(for: state.id)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func equalRing(for id: PopoverBlockID) -> some View {
        switch id {
        case .sessionRing:
            PopoverEqualRing(
                label: String(localized: "metric.session"),
                pct: usageStore.fiveHourPct,
                resetText: usageStore.fiveHourReset
            )
        case .weeklyRing:
            PopoverEqualRing(
                label: String(localized: "metric.weekly"),
                pct: usageStore.sevenDayPct,
                resetText: usageStore.sevenDayReset
            )
        default:
            EmptyView()
        }
    }

    // MARK: - Middle

    @ViewBuilder
    private var middleZone: some View {
        let visibleMiddle = layout.middle.filter { !$0.hidden }
        if visibleMiddle.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 12) {
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
        case .sessionPaceBar:
            if let pacing = usageStore.fiveHourPacing {
                PopoverPacingRow(
                    label: String(localized: "pacing.session.label"),
                    pacing: pacing
                )
            }
        case .weeklyPaceBar:
            if let pacing = usageStore.pacingResult {
                PopoverPacingRow(
                    label: String(localized: "pacing.weekly.label"),
                    pacing: pacing
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

    // MARK: - Helpers

    private func isBlockVisible(_ id: PopoverBlockID) -> Bool {
        layout.hero.contains { $0.id == id && !$0.hidden }
    }
}

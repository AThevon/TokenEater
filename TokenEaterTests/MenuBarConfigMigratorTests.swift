import Testing
import Foundation

@Suite("MenuBarConfigMigrator")
struct MenuBarConfigMigratorTests {

    private func migrate(
        pins: Set<MetricID>,
        style: MenuBarStyle = .classic,
        sessionMode: PacingDisplayMode = .dotDelta,
        weeklyMode: PacingDisplayMode = .dotDelta,
        resetFormat: ResetDisplayFormat = .relative,
        shape: PacingShape = .circle
    ) -> MenuBarComposition {
        MenuBarConfigMigrator.migrate(
            pinnedMetrics: pins,
            menuBarStyle: style,
            sessionPacingDisplayMode: sessionMode,
            weeklyPacingDisplayMode: weeklyMode,
            resetDisplayFormat: resetFormat,
            pacingShape: shape
        )
    }

    @Test("default pins in classic style become label+value session then weekly")
    func classicDefault() {
        let result = migrate(pins: [.fiveHour, .sevenDay])
        #expect(result.segments.map(\.kind) == [.session, .weekly])
        #expect(result.segments.allSatisfy { $0.style == .labelValue })
    }

    @Test("order follows the legacy render order regardless of set iteration")
    func orderPreserved() {
        // Pins given in a jumbled set; output must be the fixed legacy order.
        let result = migrate(pins: [.weeklyPacing, .fiveHour, .serviceStatus, .sevenDay])
        #expect(result.segments.map(\.kind) == [.serviceStatus, .session, .weekly, .weeklyPacing])
    }

    @Test("mono style maps usage segments to the mono style")
    func monoStyle() {
        let result = migrate(pins: [.fiveHour], style: .mono)
        #expect(result.segments[0].style == .mono)
    }

    @Test("badge style maps every segment to pill")
    func badgeStyle() {
        let result = migrate(pins: [.fiveHour, .sessionReset, .weeklyPacing, .serviceStatus], style: .badge)
        #expect(result.segments.allSatisfy { $0.style == .pill })
    }

    @Test("pacing segments take their per-metric display mode as style")
    func pacingModes() {
        let result = migrate(
            pins: [.sessionPacing, .weeklyPacing],
            sessionMode: .dot, weeklyMode: .delta
        )
        #expect(result.segments.first { $0.kind == .sessionPacing }?.style == .dot)
        #expect(result.segments.first { $0.kind == .weeklyPacing }?.style == .delta)
    }

    @Test("reset format and pacing shape are carried into options")
    func optionsCarried() {
        let result = migrate(
            pins: [.sessionReset, .sessionPacing],
            resetFormat: .both, shape: .diamond
        )
        #expect(result.segments.first { $0.kind == .sessionReset }?.options.resetFormat == .both)
        #expect(result.segments.first { $0.kind == .sessionPacing }?.options.pacingShape == .diamond)
    }

    @Test("presence-gated pins are KEPT (render-time gating handles absence, so nothing is lost)")
    func presenceGatedPinsKept() {
        // The old menu bar kept the pin and re-showed it when the metric
        // returned; the migrator must not drop it (extra credits' isEnabled is
        // transient). Render-time isSegmentAvailable hides it while absent.
        let result = migrate(pins: [.fiveHour, .fable, .extraCredits])
        let kinds = result.segments.map(\.kind)
        #expect(kinds.contains(.session))
        #expect(kinds.contains(.fable))
        #expect(kinds.contains(.extraCredits))
    }

    @Test("badge pacing preserves the display mode: dotDelta -> pill, dot -> dot, delta -> delta")
    func badgePacingHonorsMode() {
        let dotDelta = migrate(pins: [.sessionPacing], style: .badge, sessionMode: .dotDelta)
        #expect(dotDelta.segments.first?.style == .pill)
        let dot = migrate(pins: [.sessionPacing], style: .badge, sessionMode: .dot)
        #expect(dot.segments.first?.style == .dot)
        let delta = migrate(pins: [.sessionPacing], style: .badge, sessionMode: .delta)
        #expect(delta.segments.first?.style == .delta)
    }

    @Test("every migrated segment has a legal style for its kind, across all styles and pacing modes")
    func migratedSegmentsValid() {
        let modes: [PacingDisplayMode] = [.dot, .dotDelta, .delta]
        for style in MenuBarStyle.allCases {
            for mode in modes {
                let result = migrate(pins: Set(MetricID.allCases), style: style, sessionMode: mode, weeklyMode: mode)
                for seg in result.segments {
                    #expect(seg.kind.allowedStyles.contains(seg.style),
                            "\(style)/\(mode): \(seg.kind) got illegal \(seg.style)")
                }
            }
        }
    }

    @Test("empty pins produce an empty (but valid) composition")
    func emptyPins() {
        let result = migrate(pins: [])
        #expect(result.segments.isEmpty)
        #expect(!result.hasVisibleContent)
    }
}

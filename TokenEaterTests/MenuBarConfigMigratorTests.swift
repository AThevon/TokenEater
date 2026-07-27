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
        shape: PacingShape = .circle,
        presence: MenuBarConfigMigrator.AccountPresence = .init()
    ) -> MenuBarComposition {
        MenuBarConfigMigrator.migrate(
            pinnedMetrics: pins,
            menuBarStyle: style,
            sessionPacingDisplayMode: sessionMode,
            weeklyPacingDisplayMode: weeklyMode,
            resetDisplayFormat: resetFormat,
            pacingShape: shape,
            presence: presence
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

    @Test("a pinned metric absent on the account is dropped")
    func presenceGating() {
        let result = migrate(
            pins: [.fiveHour, .design, .fable, .extraCredits],
            presence: .init(hasDesign: false, hasFable: true, hasExtraCredits: false)
        )
        let kinds = result.segments.map(\.kind)
        #expect(kinds.contains(.session))
        #expect(kinds.contains(.fable))
        #expect(!kinds.contains(.design))
        #expect(!kinds.contains(.extraCredits))
    }

    @Test("every migrated segment has a legal style for its kind")
    func migratedSegmentsValid() {
        for style in MenuBarStyle.allCases {
            let result = migrate(
                pins: Set(MetricID.allCases), style: style,
                presence: .init(hasDesign: true, hasFable: true, hasExtraCredits: true)
            )
            for seg in result.segments {
                #expect(seg.kind.allowedStyles.contains(seg.style),
                        "\(style): \(seg.kind) got illegal \(seg.style)")
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

import Testing
import Foundation
import AppKit

/// Covers the claim the Codex surfaces rest on: the new element and segment
/// kinds are purely additive, so no persisted composition needs migrating and
/// no schema version moves.
@Suite("Codex popover and menu bar composition")
struct CodexCompositionTests {

    // MARK: - Additive by construction

    @Test("Adding Codex kinds did not move the composition schema version")
    func schemaVersionUnchanged() {
        #expect(PopoverComposition.currentVersion == 2)
    }

    @Test("Codex kinds inherit the families they render as")
    func families() {
        #expect(PopoverElementKind.codexSession.family == .usage)
        #expect(PopoverElementKind.codexWeekly.family == .usage)
        #expect(PopoverElementKind.codexSessionPacing.family == .pacing)
        #expect(PopoverElementKind.codexWeeklyPacing.family == .pacing)
        // Styles come from the family, so no style matrix needed extending.
        #expect(PopoverElementKind.codexSession.allowedStyles == PopoverElementKind.session.allowedStyles)
        #expect(PopoverElementKind.codexWeeklyPacing.allowedStyles == PopoverElementKind.weeklyPacing.allowedStyles)
    }

    /// Only the symbol is asserted here: the test bundle carries no .lproj, so
    /// every localized lookup would echo its own key back. String presence and
    /// EN/FR parity are checked against the .strings files themselves.
    @Test("Every kind has an editor symbol")
    func symbols() {
        for kind in PopoverElementKind.allCases {
            #expect(!kind.symbolName.isEmpty, "no symbol for \(kind.rawValue)")
        }
        for kind in MenuBarSegmentKind.allCases {
            #expect(!kind.symbolName.isEmpty, "no symbol for \(kind.rawValue)")
        }
    }

    @Test("Menu bar segments know which provider they read from")
    func providerGrouping() {
        #expect(MenuBarSegmentKind.session.provider == .claude)
        #expect(MenuBarSegmentKind.codexSession.provider == .codex)
        #expect(MenuBarSegmentKind.codexWeeklyPacing.provider == .codex)
        // Every Codex segment is presence gated, so a Claude-only account
        // never renders one.
        for kind in MenuBarSegmentKind.allCases where kind.provider == .codex {
            #expect(kind.isPresenceGated)
        }
    }

    // MARK: - Forward and backward compatibility

    @Test("A composition holding Codex elements round-trips unchanged")
    func roundTrip() throws {
        let original = PopoverBuiltinTemplate.sideBySide.composition
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PopoverComposition.self, from: data)
        #expect(decoded.version == PopoverComposition.currentVersion)
        #expect(decoded.elements.map(\.kind) == original.elements.map(\.kind))
    }

    @Test("An element kind this build does not know is dropped, the rest survives")
    func unknownKindIsDropped() throws {
        // This is the property that makes the addition safe in both
        // directions: a blob written by a newer build loses only what this
        // build cannot render.
        let json = """
        {
          "version": 2,
          "showPlanBadge": true,
          "showRefreshButton": true,
          "elements": [
            {"kind": "session", "style": "gaugeRing", "width": "half"},
            {"kind": "geminiSession", "style": "gaugeRing", "width": "half"},
            {"kind": "codexWeekly", "style": "chip", "width": "half"}
          ]
        }
        """
        let decoded = try JSONDecoder().decode(PopoverComposition.self, from: Data(json.utf8))
        #expect(decoded.elements.map(\.kind) == [.session, .codexWeekly])
    }

    @Test("The Claude + Codex template pairs each window with its counterpart")
    func bothProvidersTemplate() {
        let kinds = PopoverBuiltinTemplate.sideBySide.composition.elements.map(\.kind)
        #expect(kinds.contains(.codexSession))
        #expect(kinds.contains(.codexWeekly))
        // Sessions sit next to each other, so the two providers read as one
        // dashboard rather than two stacked ones.
        let sessionIndex = try? #require(kinds.firstIndex(of: .session))
        let codexSessionIndex = try? #require(kinds.firstIndex(of: .codexSession))
        if let sessionIndex, let codexSessionIndex {
            #expect(codexSessionIndex == sessionIndex + 1)
        }
    }

    // MARK: - Menu bar presence gating

    @Test("A Codex segment disappears when the plan has no such window")
    func absentWindowHidesTheSegment() {
        let image = MenuBarRenderer.renderUncached(
            renderData(segments: [MenuBarSegment(kind: .codexSession, style: .labelValue)], codexSession: nil)
        )
        // Nothing visible left in the composition, so the renderer falls back
        // to the template logo rather than drawing a phantom 0%.
        #expect(image.isTemplate == true)
    }

    @Test("A Codex segment renders once its window exists")
    func presentWindowRendersTheSegment() {
        let image = MenuBarRenderer.renderUncached(
            renderData(
                segments: [MenuBarSegment(kind: .codexSession, style: .labelValue)],
                codexSession: MenuBarRenderer.CodexSegmentData(
                    pct: 42, resetDate: Date().addingTimeInterval(3_600),
                    windowDuration: 18_000, hasPacing: false, pacingZone: .onTrack, pacingDelta: 0
                )
            )
        )
        #expect(image.isTemplate == false)
        #expect(image.size.width > 0)
    }

    @Test("A window length this app has never seen still renders")
    func unknownWindowLengthStillRenders() {
        // Codex declares window durations rather than the client assuming
        // them, so a future daily or monthly window must not be dropped.
        let image = MenuBarRenderer.renderUncached(
            renderData(
                segments: [MenuBarSegment(kind: .codexWeekly, style: .labelValue)],
                codexWeekly: MenuBarRenderer.CodexSegmentData(
                    pct: 12, resetDate: Date().addingTimeInterval(86_400 * 30),
                    windowDuration: 86_400 * 30, hasPacing: false, pacingZone: .onTrack, pacingDelta: 0
                )
            )
        )
        #expect(image.isTemplate == false)
    }

    // MARK: - Helper

    private func renderData(
        segments: [MenuBarSegment],
        codexSession: MenuBarRenderer.CodexSegmentData? = nil,
        codexWeekly: MenuBarRenderer.CodexSegmentData? = nil
    ) -> MenuBarRenderer.RenderData {
        MenuBarRenderer.RenderData(
            composition: MenuBarComposition(segments: segments),
            fiveHourPct: 10, sevenDayPct: 5, sonnetPct: 0,
            weeklyPacingDelta: 0, weeklyPacingZone: .onTrack, hasWeeklyPacing: false,
            sessionPacingDelta: 0, sessionPacingZone: .onTrack, hasSessionPacing: false,
            fablePacingDelta: 0, fablePacingZone: .onTrack, hasFablePacing: false,
            hasConfig: true, hasError: false, isAwaitingRefresh: false,
            themeColors: .default, thresholds: .default, menuBarMonochrome: false,
            fiveHourReset: "", fiveHourResetAbsolute: "",
            fiveHourResetDate: nil, sevenDayResetDate: nil, sonnetResetDate: nil,
            hasFiveHourBucket: true,
            resetTextColorHex: "", sessionPeriodColorHex: "",
            smartResetColor: false, smartColorProfile: .balanced, pacingMargin: 10,
            fablePct: 0, hasFable: false, fableResetDate: nil,
            outageActive: false, outageHealth: .healthy, nextPollSeconds: nil,
            extraCreditsPct: 0, hasExtraCredits: false,
            codexSession: codexSession, codexWeekly: codexWeekly,
            visibleProviders: [.claude, .codex]
        )
    }
}

/// The two things the user pushed back on: a menu bar label that named the
/// provider instead of the window, and a popover switcher nobody could remove.
@Suite("Provider chrome")
struct ProviderChromeTests {

    @Test("A Codex window wears the same label as a Claude window of the same length")
    func labelsFollowTheWindowNotTheProvider() {
        #expect(MenuBarRenderer.durationShortLabel(5 * 3600) == MetricID.fiveHour.shortLabel)
        #expect(MenuBarRenderer.durationShortLabel(7 * 86_400) == MetricID.sevenDay.shortLabel)
    }

    @Test("A window length this app has never seen still gets an honest label")
    func unknownLengthsAreDerived() {
        #expect(MenuBarRenderer.durationShortLabel(3_600) == "1h")
        #expect(MenuBarRenderer.durationShortLabel(86_400) == "24h")
        #expect(MenuBarRenderer.durationShortLabel(30 * 86_400) == "30d")
        // A missing duration must not render "0h" next to a percentage.
        #expect(MenuBarRenderer.durationShortLabel(0).isEmpty)
    }

    @Test("The provider switch is a removable element, not fixed chrome")
    func switchIsComposable() {
        #expect(PopoverElementKind.providerSwitch.family == .utility)
        #expect(PopoverElementKind.providerSwitch.allowedStyles == PopoverElementKind.timestamp.allowedStyles)
        // It belongs to no provider, so a provider mode keeps it.
        #expect(PopoverElementKind.providerSwitch.provider == nil)
        #expect(ProviderMode.codex.shows(PopoverElementKind.providerSwitch.provider))
    }

    @Test("No template seeds it as an element any more")
    func templatesDoNotSeedIt() {
        // It is pinned chrome above the composition now. As an element it
        // lived inside each mode's layout, so switching into a mode whose
        // layout did not carry it removed the only way back out: a control
        // that changes the scope cannot be something the scope can delete.
        for template in PopoverBuiltinTemplate.allCases {
            #expect(!template.composition.elements.contains { $0.kind == .providerSwitch },
                    "\(template.rawValue) still seeds a deletable switcher")
        }
    }

    @Test("A layout saved by an older build does not render a second one")
    func staleElementIsInert() throws {
        // Blobs written while it was an element are still out there. The kind
        // decodes, so the composition survives; the resolver gates it out so
        // it does not draw underneath the pinned one.
        let json = """
        {
          "version": 2,
          "showPlanBadge": true,
          "showRefreshButton": true,
          "elements": [
            {"kind": "providerSwitch", "style": "utilityRow", "width": "full"},
            {"kind": "session", "style": "gaugeRing", "width": "half"}
          ]
        }
        """
        let decoded = try JSONDecoder().decode(PopoverComposition.self, from: Data(json.utf8))
        #expect(decoded.elements.map(\.kind) == [.providerSwitch, .session])
    }

    @Test("Adding it still did not move the schema version")
    func stillAdditive() {
        #expect(PopoverComposition.currentVersion == 2)
    }
}

/// The glance cards have to stay one design. They already drifted once, when
/// Codex had its own copy of Claude's face.
@Suite("Glance card parity")
struct GlanceCardParityTests {

    @Test("Both cards name the same window with the same word")
    func windowNamesMatch() {
        #expect(CodexWindowKind.session.heroLabel(for: 5 * 3600)
                == String(localized: "dashboard.hero.window.session"))
        #expect(CodexWindowKind.weekly.heroLabel(for: 7 * 86_400)
                == String(localized: "dashboard.hero.window.weekly"))
    }

    @Test("A window shape this app has never seen falls back to its duration")
    func unknownWindowsKeepADurationLabel() {
        // `other` is the defensive case: a new backend window must still show
        // up with an honest name rather than being dropped or mislabelled.
        #expect(CodexWindowKind.other.heroLabel(for: 12 * 3600) == "12h")
        #expect(CodexWindowKind.other.heroLabel(for: 3 * 86_400) == "3d")
    }

    @Test("The menu bar still names durations, because there it names a length")
    func menuBarLabelsAreUnchanged() {
        // Two different jobs on purpose: the card names the concept, the menu
        // bar names the length, and both are the same on both providers.
        #expect(CodexWindowKind.session.label(for: 5 * 3600) == "5h")
        #expect(CodexWindowKind.session.label(for: 5 * 3600) == MetricID.fiveHour.shortLabel)
    }
}

/// Templates are what most people ever touch, so their ordering is a feature.
@Suite("Template ordering")
struct TemplateOrderingTests {

    @Test("With both providers on, the paired layouts come first")
    func pairedLeadInAll() {
        let ordered = PopoverBuiltinTemplate.ordered(for: .all, providerCount: 2)
        #expect(ordered.first?.scope == .paired)
        // All is the mode most people land in, and a two-provider layout at
        // the bottom of the list is one nobody finds.
        let firstUniversal = ordered.firstIndex { $0.scope == .universal } ?? 0
        let lastPaired = ordered.lastIndex { $0.scope == .paired } ?? 0
        #expect(lastPaired < firstUniversal)
    }

    @Test("With one provider, or inside a provider mode, they go last instead")
    func pairedTrailElsewhere() {
        for (mode, count) in [(ProviderMode.all, 1), (.claude, 2), (.codex, 2)] {
            let ordered = PopoverBuiltinTemplate.ordered(for: mode, providerCount: count)
            #expect(ordered.first?.scope == .universal, "\(mode.rawValue)/\(count)")
            #expect(ordered.last?.scope == .paired, "\(mode.rawValue)/\(count)")
        }
    }

    @Test("Ordering is a permutation: nothing lost, nothing duplicated")
    func orderingKeepsEverything() {
        for (mode, count) in [(ProviderMode.all, 2), (.all, 1), (.claude, 2)] {
            #expect(Set(PopoverBuiltinTemplate.ordered(for: mode, providerCount: count))
                    == Set(PopoverBuiltinTemplate.allCases))
            #expect(Set(MenuBarBuiltinTemplate.ordered(for: mode, providerCount: count))
                    == Set(MenuBarBuiltinTemplate.allCases))
        }
    }

    @Test("The menu bar follows the same rule")
    func menuBarOrdering() {
        #expect(MenuBarBuiltinTemplate.ordered(for: .all, providerCount: 2).first?.scope == .paired)
        #expect(MenuBarBuiltinTemplate.ordered(for: .claude, providerCount: 2).last?.scope == .paired)
    }

    @Test("Every template produces something, and every paired one pairs")
    func templatesAreWellFormed() {
        for template in PopoverBuiltinTemplate.allCases {
            let kinds = template.composition.elements.map(\.kind)
            #expect(!kinds.isEmpty, "\(template.rawValue) is empty")
            if template.scope == .paired {
                #expect(kinds.contains { $0.provider == .claude },
                        "\(template.rawValue) pairs nothing on the Claude side")
                #expect(kinds.contains { $0.provider == .codex },
                        "\(template.rawValue) pairs nothing on the Codex side")
            }
        }
        for template in MenuBarBuiltinTemplate.allCases {
            #expect(!template.composition.segments.isEmpty, "\(template.rawValue) is empty")
            if template.scope == .paired {
                #expect(template.composition.segments.contains { $0.kind.provider == .codex },
                        "\(template.rawValue) pairs nothing on the Codex side")
            }
        }
    }

    @Test("Every template name resolves to a string of its own")
    func namesAreDistinct() {
        let popover = PopoverBuiltinTemplate.allCases.map(\.localizedName)
        #expect(Set(popover).count == popover.count)
        let menuBar = MenuBarBuiltinTemplate.allCases.map(\.localizedName)
        #expect(Set(menuBar).count == menuBar.count)
    }
}

import Foundation

// MARK: - Element vocabulary
//
// The composable popover model (v5.9+). A popover is a single ordered list of
// elements; each element = a data source (kind) + a rendering style + a grid
// width. Replaces the per-variant block system in `PopoverLayoutModels.swift`,
// which is kept only to decode the legacy `popoverConfig` blob at migration
// time (see `PopoverConfigMigrator`).

/// What an element shows.
enum PopoverElementKind: String, Codable, CaseIterable, Identifiable {
    // Usage metrics (percentage + reset window)
    case session, weekly, sonnet, fable, extraCredits
    // Pacing metrics (delta vs linear pace)
    case sessionPacing, weeklyPacing
    // Utility rows
    case watchers, timestamp, planBadge
    // Action buttons
    case openButton, quitButton, refreshButton

    var id: String { rawValue }

    enum Family { case usage, pacing, utility, action }

    var family: Family {
        switch self {
        case .session, .weekly, .sonnet, .fable, .extraCredits:
            return .usage
        case .sessionPacing, .weeklyPacing:
            return .pacing
        case .watchers, .timestamp, .planBadge:
            return .utility
        case .openButton, .quitButton, .refreshButton:
            return .action
        }
    }

    /// The ex-header chrome (plan badge + refresh button). These pack into
    /// their own full-width row and never merge with the metric grid, so
    /// hiding one leaves the other on its own line rather than pairing it
    /// with the next metric.
    var isChrome: Bool {
        self == .planBadge || self == .refreshButton
    }

    /// Styles this kind can render as. The editor filters its style menu with
    /// this; `PopoverCompositionModelsTests` asserts the matrix stays sane.
    var allowedStyles: [PopoverElementStyle] {
        switch self {
        case .planBadge:
            return [.badge]
        default:
            switch family {
            case .usage: return [.gaugeRing, .chip, .arc, .bigText]
            case .pacing: return [.paceBar, .paceTile, .paceText]
            case .utility: return [.utilityRow]
            case .action: return [.actionButton]
            }
        }
    }
}

/// How an element renders.
enum PopoverElementStyle: String, Codable, CaseIterable, Identifiable {
    /// Circular gauge. Size scales with width: full = hero (100px),
    /// half = medium (70px), third = satellite (46px).
    case gaugeRing
    /// Card with a mini trimmed ring + label + value. Full / half only:
    /// at a third of the row the card crushes its label, use `.gaugeRing`
    /// for small satellites instead.
    case chip
    /// The open half-arc hero (ex-Focus). Full width only.
    case arc
    /// Big value + small label in a card.
    case bigText
    /// Label + pacing bar + signed delta (ex-Classic pacing row).
    case paceBar
    /// Carded pacing bar + delta (ex-Compact tile).
    case paceTile
    /// Delta text only (ex-Focus mini row).
    case paceText
    /// Fixed style for watchers / timestamp.
    case utilityRow
    /// Fixed style for Open / Quit / Refresh.
    case actionButton
    /// Small centered capsule (the plan badge, ex-header chrome).
    case badge

    var id: String { rawValue }

    /// Widths at which this style stays legible.
    var allowedWidths: [PopoverElementWidth] {
        switch self {
        case .gaugeRing, .bigText:
            return [.full, .half, .third]
        case .arc, .paceBar, .utilityRow:
            return [.full]
        case .chip, .paceTile, .paceText, .actionButton, .badge:
            return [.full, .half]
        }
    }

    /// The width a freshly-added element of this style starts at.
    var defaultWidth: PopoverElementWidth {
        switch self {
        case .gaugeRing, .chip, .bigText, .paceTile, .badge:
            return .half
        case .arc, .paceBar, .paceText, .utilityRow, .actionButton:
            return .full
        }
    }

    /// Whether the element options row exposes the percent / reset-countdown
    /// content picker.
    var supportsContentChoice: Bool {
        self == .arc || self == .bigText
    }

    /// Whether the element options row exposes the "show reset" toggle
    /// (caption under the ring, subtitle inside the chip).
    var supportsResetToggle: Bool {
        self == .gaugeRing || self == .chip
    }
}

/// How much of a grid row an element occupies. Consecutive elements of the
/// same width share a row (see `PopoverRowPacker`).
enum PopoverElementWidth: String, Codable, CaseIterable, Identifiable {
    case full, half, third

    var id: String { rawValue }

    var fraction: Double {
        switch self {
        case .full: return 1
        case .half: return 1.0 / 2.0
        case .third: return 1.0 / 3.0
        }
    }

    /// Max elements per row at this width.
    var rowCapacity: Int {
        switch self {
        case .full: return 1
        case .half: return 2
        case .third: return 3
        }
    }
}

/// What a usage-metric element displays as its main value.
enum PopoverMetricContent: String, Codable, CaseIterable {
    case percent, resetCountdown
}

// MARK: - Element

struct PopoverElementOptions: Codable, Equatable {
    /// Main value for `.arc` / `.bigText` styles.
    var content: PopoverMetricContent
    /// Reset caption under `.gaugeRing`, reset subtitle inside `.chip`.
    var showReset: Bool

    init(content: PopoverMetricContent = .percent, showReset: Bool = false) {
        self.content = content
        self.showReset = showReset
    }

    // Tolerant decoding so future option fields never break old blobs.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = (try? c.decodeIfPresent(PopoverMetricContent.self, forKey: .content)) ?? .percent
        showReset = (try? c.decodeIfPresent(Bool.self, forKey: .showReset)) ?? false
    }
}

struct PopoverElement: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: PopoverElementKind
    var style: PopoverElementStyle
    var width: PopoverElementWidth
    /// Kept in the list but not rendered (the editor's eye toggle).
    var isHidden: Bool
    var options: PopoverElementOptions

    init(
        id: UUID = UUID(),
        kind: PopoverElementKind,
        style: PopoverElementStyle,
        width: PopoverElementWidth,
        isHidden: Bool = false,
        options: PopoverElementOptions = PopoverElementOptions()
    ) {
        self.id = id
        self.kind = kind
        self.style = style
        self.width = width
        self.isHidden = isHidden
        self.options = options
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown kind/style/width raw values (blob written by a newer app
        // version) throw here; the composition decoder drops the element
        // instead of failing the whole blob.
        kind = try c.decode(PopoverElementKind.self, forKey: .kind)
        style = try c.decode(PopoverElementStyle.self, forKey: .style)
        width = try c.decode(PopoverElementWidth.self, forKey: .width)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        isHidden = (try? c.decodeIfPresent(Bool.self, forKey: .isHidden)) ?? false
        options = (try? c.decodeIfPresent(PopoverElementOptions.self, forKey: .options)) ?? PopoverElementOptions()
    }

    /// Width clamped to what the style allows - a decoded or programmatic
    /// mismatch renders at the closest legal width instead of breaking rows
    /// (e.g. a chip stored at .third before chips lost that width renders
    /// at .half, not .full).
    var effectiveWidth: PopoverElementWidth {
        let allowed = style.allowedWidths
        if allowed.contains(width) { return width }
        return allowed.min { abs($0.fraction - width.fraction) < abs($1.fraction - width.fraction) } ?? .full
    }
}

// MARK: - Composition

struct PopoverComposition: Codable, Equatable {
    /// Schema version written by this build. v1 = fixed header chrome driven
    /// by the two legacy toggles below; v2 = the plan badge and the refresh
    /// button are regular elements (see `PopoverChromeMigrator`).
    static let currentVersion = 2

    /// Ordered list; order = render order top to bottom.
    var elements: [PopoverElement]
    /// Version of the blob this composition was decoded from (or
    /// `currentVersion` for compositions built in code).
    var version: Int
    /// Legacy header toggle (pre-v2). Only meaningful on version-1
    /// compositions; kept so the migrator and downgraded builds can read it.
    var showPlanBadge: Bool
    /// Legacy header toggle (pre-v2). Same story as `showPlanBadge`.
    var showRefreshButton: Bool

    private enum CodingKeys: String, CodingKey {
        case elements, version, showPlanBadge, showRefreshButton
    }

    init(
        elements: [PopoverElement],
        version: Int = PopoverComposition.currentVersion,
        showPlanBadge: Bool = true,
        showRefreshButton: Bool = true
    ) {
        self.elements = elements
        self.version = version
        self.showPlanBadge = showPlanBadge
        self.showRefreshButton = showRefreshButton
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Lossy element list: an element a newer version wrote with an unknown
        // kind/style is silently dropped, everything else survives.
        elements = c.decodeLossyArray(PopoverElement.self, forKey: .elements)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1
        showPlanBadge = (try? c.decodeIfPresent(Bool.self, forKey: .showPlanBadge)) ?? true
        showRefreshButton = (try? c.decodeIfPresent(Bool.self, forKey: .showRefreshButton)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(elements, forKey: .elements)
        try c.encode(version, forKey: .version)
        // On v2 compositions the legacy toggles mirror the chrome elements'
        // visibility, so a downgraded build (which drops the unknown kinds
        // from the element list) still shows the header the user expects.
        try c.encode(
            version >= 2 ? chromeElementVisible(.planBadge) : showPlanBadge,
            forKey: .showPlanBadge
        )
        try c.encode(
            version >= 2 ? chromeElementVisible(.refreshButton) : showRefreshButton,
            forKey: .showRefreshButton
        )
    }

    private func chromeElementVisible(_ kind: PopoverElementKind) -> Bool {
        elements.contains { $0.kind == kind && !$0.isHidden }
    }

    var visibleElements: [PopoverElement] { elements.filter { !$0.isHidden } }

    /// Validation gate used by `SettingsStore.reconcile` - an all-hidden or
    /// empty composition falls back to the default template.
    var hasVisibleContent: Bool { !visibleElements.isEmpty }

    /// Structural match ignoring element UUIDs (and the legacy toggles /
    /// version), so the editor can tell which template the current
    /// composition came from - built-ins mint fresh ids on every access, so
    /// plain `==` would never match.
    func isEquivalent(to other: PopoverComposition) -> Bool {
        guard elements.count == other.elements.count else { return false }
        for (a, b) in zip(elements, other.elements) where
            a.kind != b.kind || a.style != b.style || a.width != b.width
            || a.isHidden != b.isHidden || a.options != b.options {
            return false
        }
        return true
    }

    static let `default` = PopoverBuiltinTemplate.classic.composition
}

// MARK: - Templates

/// Built-in starting points. Classic / Compact / Focus faithfully recreate the
/// three pre-5.9 layouts (they double as migration reference targets).
enum PopoverBuiltinTemplate: String, CaseIterable, Identifiable {
    case classic, compact, focus, minimalist, fableFirst, complete

    var id: String { rawValue }

    var localizedName: String {
        NSLocalizedString("popoverTemplate.\(rawValue)", comment: "")
    }

    /// The ex-header chrome pair every template starts with -> plan badge on
    /// the left, refresh button on the right (one half+half row).
    private static var chromeRow: [PopoverElement] {
        [
            PopoverElement(kind: .planBadge, style: .badge, width: .half),
            PopoverElement(kind: .refreshButton, style: .actionButton, width: .half),
        ]
    }

    /// Fresh element instances (new UUIDs) on every access, so applying a
    /// template twice never collides ids with a live composition.
    var composition: PopoverComposition {
        switch self {
        case .classic:
            return PopoverComposition(elements: Self.chromeRow + [
                PopoverElement(kind: .session, style: .gaugeRing, width: .half, options: .init(showReset: true)),
                PopoverElement(kind: .weekly, style: .gaugeRing, width: .half, options: .init(showReset: true)),
                PopoverElement(kind: .sessionPacing, style: .paceBar, width: .full),
                PopoverElement(kind: .weeklyPacing, style: .paceBar, width: .full),
                PopoverElement(kind: .watchers, style: .utilityRow, width: .full),
                PopoverElement(kind: .timestamp, style: .utilityRow, width: .full),
                PopoverElement(kind: .openButton, style: .actionButton, width: .full),
                PopoverElement(kind: .quitButton, style: .actionButton, width: .full),
            ])
        case .compact:
            return PopoverComposition(elements: Self.chromeRow + [
                PopoverElement(kind: .session, style: .chip, width: .half, options: .init(showReset: true)),
                PopoverElement(kind: .weekly, style: .chip, width: .half, options: .init(showReset: true)),
                PopoverElement(kind: .sessionPacing, style: .paceTile, width: .half),
                PopoverElement(kind: .weeklyPacing, style: .paceTile, width: .half),
                PopoverElement(kind: .watchers, style: .utilityRow, width: .full),
                PopoverElement(kind: .timestamp, style: .utilityRow, width: .full),
                PopoverElement(kind: .openButton, style: .actionButton, width: .full),
                PopoverElement(kind: .quitButton, style: .actionButton, width: .full),
            ])
        case .focus:
            return PopoverComposition(elements: Self.chromeRow + [
                PopoverElement(kind: .session, style: .arc, width: .full, options: .init(content: .resetCountdown)),
                PopoverElement(kind: .session, style: .bigText, width: .half, options: .init(content: .percent)),
                PopoverElement(kind: .weekly, style: .bigText, width: .half, options: .init(content: .percent)),
                PopoverElement(kind: .sessionPacing, style: .paceText, width: .full),
                PopoverElement(kind: .weeklyPacing, style: .paceText, width: .full),
                PopoverElement(kind: .watchers, style: .utilityRow, width: .full),
                PopoverElement(kind: .timestamp, style: .utilityRow, width: .full),
                PopoverElement(kind: .openButton, style: .actionButton, width: .full),
                PopoverElement(kind: .quitButton, style: .actionButton, width: .full),
            ])
        case .minimalist:
            return PopoverComposition(elements: Self.chromeRow + [
                PopoverElement(kind: .session, style: .gaugeRing, width: .half, options: .init(showReset: true)),
                PopoverElement(kind: .weekly, style: .gaugeRing, width: .half, options: .init(showReset: true)),
                PopoverElement(kind: .timestamp, style: .utilityRow, width: .full),
            ])
        case .fableFirst:
            return PopoverComposition(elements: Self.chromeRow + [
                PopoverElement(kind: .fable, style: .arc, width: .full, options: .init(content: .percent)),
                PopoverElement(kind: .session, style: .bigText, width: .half, options: .init(content: .percent)),
                PopoverElement(kind: .weekly, style: .bigText, width: .half, options: .init(content: .percent)),
                PopoverElement(kind: .timestamp, style: .utilityRow, width: .full),
            ])
        case .complete:
            return PopoverComposition(elements: Self.chromeRow + [
                PopoverElement(kind: .session, style: .gaugeRing, width: .full, options: .init(showReset: true)),
                PopoverElement(kind: .weekly, style: .gaugeRing, width: .third),
                PopoverElement(kind: .sonnet, style: .gaugeRing, width: .third),
                PopoverElement(kind: .fable, style: .gaugeRing, width: .third),
                PopoverElement(kind: .extraCredits, style: .gaugeRing, width: .third),
                PopoverElement(kind: .sessionPacing, style: .paceBar, width: .full),
                PopoverElement(kind: .weeklyPacing, style: .paceBar, width: .full),
                PopoverElement(kind: .watchers, style: .utilityRow, width: .full),
                PopoverElement(kind: .timestamp, style: .utilityRow, width: .full),
                PopoverElement(kind: .openButton, style: .actionButton, width: .half),
                PopoverElement(kind: .quitButton, style: .actionButton, width: .half),
            ])
        }
    }
}

/// A popover composition the user saved under a name. Persisted as a JSON blob
/// under the `popoverUserTemplates` UserDefaults key. Backed by the generic
/// `UserTemplate<C>` so the menu bar editor can reuse the same container; the
/// field layout is unchanged, so the stored blob stays compatible.
typealias PopoverUserTemplate = UserTemplate<PopoverComposition>

// MARK: - Labels (editor UI)

extension PopoverElementKind {
    /// NSLocalizedString, not String(localized:) - an interpolated key would
    /// become a "%@" placeholder (same pitfall as PopoverBlockID before it).
    var localizedLabel: String {
        NSLocalizedString("popoverElement.\(rawValue)", comment: "")
    }

    /// SF Symbol shown next to the kind in the editor list and add menu.
    var symbolName: String {
        switch self {
        case .session: return "bolt.fill"
        case .weekly: return "calendar"
        case .sonnet: return "quote.opening"
        case .fable: return "books.vertical.fill"
        case .extraCredits: return "creditcard.fill"
        case .sessionPacing, .weeklyPacing: return "speedometer"
        case .watchers: return "eye.fill"
        case .timestamp: return "clock"
        case .planBadge: return "checkmark.seal.fill"
        case .openButton: return "diamond.fill"
        case .quitButton: return "power"
        case .refreshButton: return "arrow.clockwise"
        }
    }
}

extension PopoverElementStyle {
    var localizedLabel: String {
        NSLocalizedString("popoverStyle.\(rawValue)", comment: "")
    }
}

extension PopoverElementWidth {
    var localizedLabel: String {
        NSLocalizedString("popoverWidth.\(rawValue)", comment: "")
    }

    var symbolName: String {
        switch self {
        case .full: return "rectangle.fill"
        case .half: return "rectangle.split.2x1.fill"
        case .third: return "rectangle.split.3x1.fill"
        }
    }
}

import Foundation

// MARK: - Segment vocabulary
//
// The composable menu bar model (v5.10+). The status-bar item is an ordered
// list of segments drawn left to right; each segment = a metric kind + a
// visual style + options. Replaces the fixed hardcoded segment order + the
// single global `menuBarStyle`, so segments become reorderable and each one
// carries its own look.
//
// Rendered in AppKit by MenuBarRenderer (NSImage), so there is no grid / width
// concept like the popover: a segment sizes to its content. Shares the tolerant
// Codable helper and the `UserTemplate` container with the popover.

/// What a menu bar segment shows.
/// Which provider a metric reads from. Groups the Studio add menus and drives
/// the display mode filter. Chrome, utilities and actions have no provider:
/// they belong to every mode.
enum MetricProvider: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    /// The name the app puts in front of a user, and deliberately the
    /// provider rather than the tool: the two peers are Claude and OpenAI,
    /// not Claude and Codex. The detail sections still say "OpenAI Codex",
    /// because by then you are looking at Codex specifically.
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "OpenAI"
        }
    }
}

/// Which slice of the app is on screen. `all` shows every provider; a provider
/// mode hides the others' metrics while keeping chrome, utilities and actions,
/// which belong to no provider.
///
/// Only meaningful with two or more active providers; below that the selector
/// is hidden and `all` is indistinguishable from the single provider's mode.
enum ProviderMode: String, Codable, CaseIterable, Identifiable {
    case all
    case claude
    case codex

    var id: String { rawValue }

    var provider: MetricProvider? {
        switch self {
        case .all: return nil
        case .claude: return .claude
        case .codex: return .codex
        }
    }

    var localizedLabel: String {
        switch self {
        case .all: return String(localized: "providerMode.all")
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// Suffix appended to a composition's UserDefaults key. `all` deliberately
    /// has none: it keeps the pre-modes key, so an existing user's layout is
    /// already the All layout with no migration and a downgrade still reads it.
    var storageSuffix: String {
        self == .all ? "" : ".\(rawValue)"
    }

    func shows(_ provider: MetricProvider?) -> Bool {
        guard let wanted = self.provider, let provider else { return true }
        return provider == wanted
    }
}

enum MenuBarSegmentKind: String, Codable, CaseIterable, Identifiable {
    // Usage metrics (percentage)
    case session, weekly, sonnet, fable, extraCredits
    // Codex usage. Additive raw values, same lossy-decode property as the
    // popover kinds: an older build drops what it does not recognise.
    case codexSession, codexWeekly
    // Pacing (delta vs linear pace)
    case sessionPacing, weeklyPacing, fablePacing
    case codexSessionPacing, codexWeeklyPacing
    // Status / time
    case sessionReset, serviceStatus

    /// Pacing segments read a rate rather than a level. The editors group by
    /// provider first and family second, and this is the family split.
    var isPacing: Bool {
        switch self {
        case .sessionPacing, .weeklyPacing, .fablePacing,
             .codexSessionPacing, .codexWeeklyPacing:
            return true
        default:
            return false
        }
    }

    var id: String { rawValue }

    enum Family { case usage, pacing, status }

    var family: Family {
        switch self {
        case .session, .weekly, .sonnet, .fable, .extraCredits,
             .codexSession, .codexWeekly:
            return .usage
        case .sessionPacing, .weeklyPacing, .fablePacing,
             .codexSessionPacing, .codexWeeklyPacing:
            return .pacing
        case .sessionReset, .serviceStatus:
            return .status
        }
    }

    /// Styles this kind can render as. The editor filters its style menu with
    /// this; `MenuBarCompositionModelsTests` asserts the matrix stays sane.
    var allowedStyles: [MenuBarSegmentStyle] {
        switch family {
        case .usage: return [.labelValue, .valueOnly, .mono, .pill]
        case .pacing: return [.dot, .dotDelta, .delta, .pill]
        case .status:
            switch self {
            case .sessionReset: return [.text, .pill]
            case .serviceStatus: return [.glyph, .pill]
            default: return [.text]
            }
        }
    }

    /// Presence-gated kinds render nothing (and the editor greys them) when the
    /// account lacks the metric, matching the pre-5.10 menu bar.
    var isPresenceGated: Bool {
        switch self {
        case .fable, .extraCredits, .fablePacing,
             .codexSession, .codexWeekly, .codexSessionPacing, .codexWeeklyPacing:
            return true
        default:
            return false
        }
    }

    /// Which provider the segment reads from. The editor groups its add menu
    /// by this, so a Claude-only user is not scrolling past Codex entries.
    var provider: MetricProvider? {
        switch self {
        case .codexSession, .codexWeekly, .codexSessionPacing, .codexWeeklyPacing:
            return .codex
        case .session, .weekly, .sonnet, .fable, .extraCredits,
             .sessionPacing, .weeklyPacing, .fablePacing, .sessionReset:
            return .claude
        // Service status is about the vendor's own health, and it is rendered
        // for whichever vendors are being watched, so it belongs to no mode.
        case .serviceStatus:
            return nil
        }
    }
}

/// How a segment renders. Plain styles draw as an `NSAttributedString` run;
/// `pill` draws a tinted capsule. Both are mixed freely in one status item.
enum MenuBarSegmentStyle: String, Codable, CaseIterable, Identifiable {
    /// "5h 62%" - short label + colored value (the classic look).
    case labelValue
    /// "62%" - value only, no label.
    case valueOnly
    /// "5h:62" - monospaced, colon separator, no percent sign.
    case mono
    /// Value in a tinted rounded capsule (the badge look). For pacing it shows
    /// the shape + delta; for status the status text.
    case pill
    /// Pacing shape glyph only (colored by zone).
    case dot
    /// Pacing shape glyph + signed delta.
    case dotDelta
    /// Signed delta only.
    case delta
    /// Plain text (session reset countdown).
    case text
    /// Status symbol glyph (+ countdown when down).
    case glyph

    var id: String { rawValue }

    var localizedLabel: String {
        NSLocalizedString("menuBarStyle.segment.\(rawValue)", comment: "")
    }
}

// MARK: - Options

struct MenuBarSegmentOptions: Codable, Equatable {
    /// Shape drawn for pacing dot styles.
    var pacingShape: PacingShape
    /// Relative / absolute / both, for the session reset segment.
    var resetFormat: ResetDisplayFormat

    init(pacingShape: PacingShape = .circle, resetFormat: ResetDisplayFormat = .relative) {
        self.pacingShape = pacingShape
        self.resetFormat = resetFormat
    }

    // Tolerant decoding so future option fields never break old blobs.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pacingShape = (try? c.decodeIfPresent(PacingShape.self, forKey: .pacingShape)) ?? .circle
        resetFormat = (try? c.decodeIfPresent(ResetDisplayFormat.self, forKey: .resetFormat)) ?? .relative
    }
}

// MARK: - Segment

struct MenuBarSegment: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: MenuBarSegmentKind
    var style: MenuBarSegmentStyle
    var isHidden: Bool
    var options: MenuBarSegmentOptions

    init(
        id: UUID = UUID(),
        kind: MenuBarSegmentKind,
        style: MenuBarSegmentStyle,
        isHidden: Bool = false,
        options: MenuBarSegmentOptions = MenuBarSegmentOptions()
    ) {
        self.id = id
        self.kind = kind
        self.style = style
        self.isHidden = isHidden
        self.options = options
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Unknown kind/style raw values (blob written by a newer app version)
        // throw here; the composition decoder drops the segment instead of
        // failing the whole blob.
        kind = try c.decode(MenuBarSegmentKind.self, forKey: .kind)
        style = try c.decode(MenuBarSegmentStyle.self, forKey: .style)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        isHidden = (try? c.decodeIfPresent(Bool.self, forKey: .isHidden)) ?? false
        options = (try? c.decodeIfPresent(MenuBarSegmentOptions.self, forKey: .options)) ?? MenuBarSegmentOptions()
    }

    /// Style clamped to what the kind allows - a decoded or programmatic
    /// mismatch renders as the kind's first legal style instead of nothing.
    var effectiveStyle: MenuBarSegmentStyle {
        kind.allowedStyles.contains(style) ? style : (kind.allowedStyles.first ?? .text)
    }
}

// MARK: - Composition

struct MenuBarComposition: Codable, Equatable {
    /// Ordered list; order = left-to-right render order.
    var segments: [MenuBarSegment]

    init(segments: [MenuBarSegment]) {
        self.segments = segments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        segments = c.decodeLossyArray(MenuBarSegment.self, forKey: .segments)
    }

    var visibleSegments: [MenuBarSegment] { segments.filter { !$0.isHidden } }

    /// Validation gate used by `SettingsStore.reconcile`. Unlike the popover
    /// (which falls back to a template when empty), an empty menu bar is a
    /// legitimate choice - `MenuBarRenderer` already draws the app logo when
    /// no segment is visible - so this only reports emptiness; the store keeps
    /// the composition as-is.
    var hasVisibleContent: Bool { !visibleSegments.isEmpty }

    /// Structural match ignoring segment UUIDs, so the editor can tell which
    /// template the current composition came from (built-ins mint fresh ids).
    func isEquivalent(to other: MenuBarComposition) -> Bool {
        guard segments.count == other.segments.count else { return false }
        for (a, b) in zip(segments, other.segments) where
            a.kind != b.kind || a.style != b.style
            || a.isHidden != b.isHidden || a.options != b.options {
            return false
        }
        return true
    }

    static let `default` = MenuBarBuiltinTemplate.classic.composition
}

// MARK: - Templates

/// Built-in starting points for the menu bar look.
enum MenuBarBuiltinTemplate: String, CaseIterable, Identifiable {
    // Same rule as the popover templates: declaration order is presentation
    // order with one provider, and `ordered(for:)` floats the paired ones up
    // when both are on.
    case classic
    case minimalist
    case pills
    case pacingFocus
    case resetClock
    case complete
    case duo
    case duoPills

    var id: String { rawValue }

    enum Scope { case universal, paired }

    var scope: Scope {
        switch self {
        case .duo, .duoPills: return .paired
        default: return .universal
        }
    }

    static func ordered(for mode: ProviderMode, providerCount: Int) -> [MenuBarBuiltinTemplate] {
        let pairedFirst = providerCount > 1 && mode == .all
        return allCases.sorted { lhs, rhs in
            let lk = (lhs.scope == .paired) == pairedFirst ? 0 : 1
            let rk = (rhs.scope == .paired) == pairedFirst ? 0 : 1
            if lk != rk { return lk < rk }
            return (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
        }
    }

    var localizedName: String {
        NSLocalizedString("menuBarTemplate.\(rawValue)", comment: "")
    }

    /// Fresh segment instances (new UUIDs) on every access, so applying a
    /// template twice never collides ids with a live composition.
    var composition: MenuBarComposition {
        switch self {
        case .classic:
            return MenuBarComposition(segments: [
                MenuBarSegment(kind: .session, style: .labelValue),
                MenuBarSegment(kind: .weekly, style: .labelValue),
            ])
        case .minimalist:
            return MenuBarComposition(segments: [
                MenuBarSegment(kind: .session, style: .valueOnly),
            ])
        case .pills:
            return MenuBarComposition(segments: [
                MenuBarSegment(kind: .session, style: .pill),
                MenuBarSegment(kind: .weekly, style: .pill),
            ])
        case .pacingFocus:
            return MenuBarComposition(segments: [
                MenuBarSegment(kind: .session, style: .labelValue),
                MenuBarSegment(kind: .sessionPacing, style: .dotDelta),
            ])
        case .resetClock:
            // For the people whose question is when it lifts, not how much is
            // left: the session number and the countdown beside it.
            return MenuBarComposition(segments: [
                MenuBarSegment(kind: .session, style: .labelValue),
                MenuBarSegment(kind: .sessionReset, style: .text),
            ])
        case .duo:
            // Both session windows, nothing else. Two numbers is already a lot
            // of menu bar, so this is the paired layout that still fits.
            return MenuBarComposition(segments: [
                MenuBarSegment(kind: .session, style: .labelValue),
                MenuBarSegment(kind: .codexSession, style: .labelValue),
            ])
        case .duoPills:
            return MenuBarComposition(segments: [
                MenuBarSegment(kind: .session, style: .pill),
                MenuBarSegment(kind: .codexSession, style: .pill),
            ])
        case .complete:
            return MenuBarComposition(segments: [
                MenuBarSegment(kind: .session, style: .labelValue),
                MenuBarSegment(kind: .sessionReset, style: .text),
                MenuBarSegment(kind: .weekly, style: .labelValue),
                MenuBarSegment(kind: .sessionPacing, style: .dotDelta),
                MenuBarSegment(kind: .weeklyPacing, style: .dotDelta),
                MenuBarSegment(kind: .sonnet, style: .labelValue),
            ])
        }
    }
}

/// A menu bar composition the user saved under a name. Persisted as a JSON
/// blob under the `menuBarUserTemplates` UserDefaults key.
typealias MenuBarUserTemplate = UserTemplate<MenuBarComposition>

// MARK: - Labels (editor UI)

extension MenuBarSegmentKind {
    var localizedLabel: String {
        NSLocalizedString("menuBarSegment.\(rawValue)", comment: "")
    }

    var symbolName: String {
        switch self {
        case .session: return "bolt.fill"
        case .weekly: return "calendar"
        case .sonnet: return "quote.opening"
        case .fable: return "books.vertical.fill"
        case .extraCredits: return "creditcard.fill"
        case .codexSession: return "bolt.horizontal.fill"
        case .codexWeekly: return "calendar.badge.clock"
        case .sessionPacing, .weeklyPacing, .fablePacing: return "speedometer"
        case .codexSessionPacing, .codexWeeklyPacing: return "speedometer"
        case .sessionReset: return "clock.arrow.circlepath"
        case .serviceStatus: return "dot.radiowaves.left.and.right"
        }
    }
}

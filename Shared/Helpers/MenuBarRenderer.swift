import AppKit

enum MenuBarRenderer {
    /// Past this width the item risks sliding under the notch of a 13 or 14
    /// inch display once the system's own items are counted. Studio and the
    /// add-account sheet warn beyond it.
    static let notchSafeWidth: CGFloat = 280

    struct RenderData: Equatable {
        /// The composable menu bar: ordered segments + per-segment styles.
        /// Drives which segments appear, in what order, and how each is drawn.
        var composition: MenuBarComposition
        let fiveHourPct: Int
        let sevenDayPct: Int
        let sonnetPct: Int
        /// True only when the account's response carries a Sonnet weekly limit
        /// (a flat `seven_day_sonnet` utilization or a `limits[]` entry). Most
        /// accounts get none any more, so a Sonnet segment draws nothing then.
        /// Defaulted so callers that never show Sonnet can leave it out.
        var hasSonnet: Bool = false
        let weeklyPacingDelta: Int
        let weeklyPacingZone: PacingZone
        let hasWeeklyPacing: Bool
        let sessionPacingDelta: Int
        let sessionPacingZone: PacingZone
        let hasSessionPacing: Bool
        let fablePacingDelta: Int
        let fablePacingZone: PacingZone
        let hasFablePacing: Bool
        let hasConfig: Bool
        let hasError: Bool
        /// Token expired/unreadable but a prior snapshot exists (#218). Keep the
        /// last segments visible instead of collapsing to the bare logo, so the
        /// menu bar doesn't look broken while Claude Code refreshes.
        let isAwaitingRefresh: Bool
        let themeColors: ThemeColors
        let thresholds: UsageThresholds
        let menuBarMonochrome: Bool
        let fiveHourReset: String
        let fiveHourResetAbsolute: String
        let fiveHourResetDate: Date?
        let sevenDayResetDate: Date?
        let sonnetResetDate: Date?
        /// True when the API returned a `five_hour` bucket at all. Independent
        /// from whether `resets_at` was populated - Anthropic can return the
        /// bucket with `utilization: 0` and no `resets_at` when you're between
        /// two 5h windows. Used to keep session segments visible (with a
        /// placeholder value) instead of hiding them whenever there's a lull.
        let hasFiveHourBucket: Bool
        let resetTextColorHex: String
        let sessionPeriodColorHex: String
        let smartResetColor: Bool
        let smartColorProfile: SmartColorProfile
        let pacingMargin: Double
        let fablePct: Int
        let hasFable: Bool
        let fableResetDate: Date?
        // Outage badge (Service Status). Set by StatusBarController from
        // VendorStatusStore; kept `let` like every other RenderData field so
        // the Equatable render cache stays correct.
        let outageActive: Bool
        let outageHealth: VendorHealth
        let nextPollSeconds: Int?
        let extraCreditsPct: Int
        let hasExtraCredits: Bool
        /// The amount spent when the Extra Credits pool has no monthly limit.
        /// Non-nil replaces the always-0 percentage with that amount; nil (a
        /// limit is set) keeps the percentage.
        let extraCreditsUncappedSpend: String?
        /// Whether that uncapped amount is above zero: neutral at zero, the
        /// warning gauge colour once spent. Ignored while a limit is set.
        let extraCreditsUncappedHasSpend: Bool
        /// Nested rather than flattened into ten more fields: `RenderData` is
        /// the Equatable key of the render cache, and a nested Equatable value
        /// keeps that comparison honest without widening the struct further.
        /// nil means the plan has no such window, which is normal on Codex.
        let codexSession: CodexSegmentData?
        let codexWeekly: CodexSegmentData?
        /// Providers the user tracks, intersected with the current display
        /// mode. A segment whose provider is absent from this set draws
        /// nothing and the bar recompacts.
        var visibleProviders: Set<MetricProvider>
        /// The numbers of each running added Claude account, keyed by
        /// `AccountID.rawValue`. A Claude segment pinned to an account reads
        /// its values here; one whose account is missing (paused, removed,
        /// Claude switched off) draws nothing, like a provider switched off.
        /// Empty with a single account, which leaves the bar exactly as it was.
        var accountData: [String: RenderData] = [:]
        /// Draws "--" for every usage value: an account that is connected but
        /// has no numbers yet, as the add-account preview shows it.
        var showsPlaceholderValues: Bool = false
        /// The mark drawn before each run of one account's Claude segments,
        /// keyed by `AccountID.rawValue`, the main account included. Filled
        /// only once two Claude accounts run; empty, the bar draws no marker
        /// and keeps every rule it had with a single account.
        var accountMarkers: [String: AccountMarker] = [:]
        /// The account a Claude segment with no account of its own reads: the
        /// one Claude mode is focused on, the main one everywhere else.
        var defaultAccount: String = AccountID.main.rawValue
        /// Claude mode: the one account on screen keeps its marker, which is
        /// what says which account it is. Elsewhere a marker only appears
        /// when the bar shows runs of two accounts or more, so an account
        /// kept out of the bar does not lengthen it.
        var marksLoneAccount: Bool = false
        /// Whether this account has a usage snapshot at all. With several
        /// accounts on, one that has none draws "--" in its place instead of
        /// turning the whole bar into the logo.
        var hasNumbers: Bool = true
    }

    /// How an account's run of segments is marked: a ring in its colour,
    /// never its name. A monochrome bar, where every ring has the same
    /// colour, adds the account's initial (`AccountNameRules.monochromeInitials`).
    struct AccountMarker: Equatable {
        /// The full name, for the status item's tooltip and the monochrome
        /// initial; a colour bar never draws it.
        let label: String
        let colorHex: String
    }

    /// One thing the bar draws, in order: an account marker or a segment. The
    /// plan is computed apart from the drawing so the rule "one marker per
    /// run of an account's segments" can be checked without pixels.
    enum PlannedVisual: Equatable {
        case marker(String)
        case segment(UUID)
    }

    /// One Codex window, in the shape the renderer needs.
    struct CodexSegmentData: Equatable {
        let pct: Int
        let resetDate: Date?
        let windowDuration: TimeInterval
        let hasPacing: Bool
        /// Meaningless when `hasPacing` is false; the renderer draws its idle
        /// placeholder in that case and never reads the zone.
        let pacingZone: PacingZone
        let pacingDelta: Int
    }

    private static var cachedImage: NSImage?
    private static var cachedData: RenderData?

    static func render(_ data: RenderData) -> NSImage {
        if let cached = cachedImage, let prev = cachedData, prev == data {
            return cached
        }

        let image = renderUncached(data)
        cachedImage = image
        cachedData = data
        return image
    }

    /// Same rendering pipeline as `render(_:)` but never touches or updates
    /// the static cache. Useful for live previews that may differ from the
    /// status bar's current state and shouldn't poison it.
    static func renderUncached(_ data: RenderData) -> NSImage {
        if data.outageActive {
            return renderWithOutageBadge(data)
        }
        if !hasUsableMetrics(data) {
            return renderLogoTemplate()
        }
        return drawComposition(data).image
    }

    /// Whether the bar has numbers to draw at all. A single account with no
    /// token or a hard error has none, and the bar shows the logo as it
    /// always did. With several accounts on, each account answers for itself
    /// instead: one with nothing to show draws "--" in its run, and the bar
    /// falls back to the logo only when nothing at all is drawable.
    private static func hasUsableMetrics(_ data: RenderData) -> Bool {
        if !data.accountMarkers.isEmpty { return true }
        return data.hasConfig && (!data.hasError || data.isAwaitingRefresh)
    }

    /// `image` as a dark menu bar draws it, whatever the appearance of the
    /// view showing it. The renderer resolves `labelColor` and
    /// `secondaryLabelColor` when the image is drawn, so a sample on a dark
    /// backdrop inside a light window would get dark text on near black.
    /// SwiftUI's `colorScheme` does not reach an `NSImage`'s drawing handler;
    /// the drawing appearance does.
    static func drawnDark(_ image: NSImage) -> NSImage {
        let dark = NSImage(size: image.size, flipped: false) { rect in
            let appearance = NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()
            appearance.performAsCurrentDrawingAppearance {
                image.draw(in: rect)
            }
            return true
        }
        dark.isTemplate = false
        return dark
    }

    /// Composition render that also returns each segment's hit rectangle in the
    /// image's coordinate space. The status item ignores the rects; the editor
    /// preview overlays invisible tap targets from them (click-to-select).
    /// Mirrors `renderUncached`'s top-level dispatch so the preview matches the
    /// real item, but never composes the separate outage badge (the preview is
    /// about the composition itself).
    static func renderWithHitRects(_ data: RenderData) -> (image: NSImage, hitRects: [SegmentHitRect]) {
        if !hasUsableMetrics(data) {
            return (renderLogoTemplate(), [])
        }
        return drawComposition(data)
    }

    /// A rendered segment's frame in the metric image (origin bottom-left, as
    /// AppKit NSImage). Emitted only for the editor preview.
    struct SegmentHitRect: Equatable {
        let id: UUID
        let rect: CGRect
    }

    // MARK: - Color helpers

    private static func colorForPct(_ pct: Int, resetDate: Date?, windowDuration: TimeInterval, data: RenderData) -> NSColor {
        gaugeColor(
            pct: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            monochrome: data.menuBarMonochrome,
            smartEnabled: data.smartResetColor,
            themeColors: data.themeColors,
            thresholds: data.thresholds,
            pacingMargin: data.pacingMargin,
            smartColorProfile: data.smartColorProfile
        )
    }

    /// Resolves the gauge colour for a flat percentage.
    ///
    /// Smart Color is a *time-aware* risk model: it projects current usage
    /// against the time left in a reset window. A metric with no reset window
    /// (e.g. the Extra Credits pool) has nothing to project against, so it
    /// falls back to the static warning/critical threshold ladder. This is the
    /// rule that keeps Extra Credits coloured identically in the menu bar, the
    /// popover, the dashboard and the widgets.
    ///
    /// One exception, on every one of those surfaces: a pool with no monthly
    /// limit has no percentage to put on the ladder (it is always 0), so it
    /// shows the amount spent instead, coloured by money rather than by
    /// threshold: neutral while nothing is spent, the theme's warning gauge
    /// colour once something is. That amount never reaches this function; the
    /// menu bar colours it with `uncappedSpendColor`, the SwiftUI surfaces
    /// with `ThemeColors.uncappedSpendColor`. Internal (not private) so the
    /// windowless-fallback rule is unit-testable in isolation; `now` is
    /// injectable for deterministic tests.
    static func gaugeColor(
        pct: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        monochrome: Bool,
        smartEnabled: Bool,
        themeColors: ThemeColors,
        thresholds: UsageThresholds,
        pacingMargin: Double,
        smartColorProfile: SmartColorProfile,
        now: Date = Date()
    ) -> NSColor {
        if monochrome { return .labelColor }
        if smartEnabled, let resetDate, windowDuration > 0 {
            return themeColors.smartGaugeNSColor(
                utilization: Double(pct),
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: thresholds,
                pacingMargin: pacingMargin,
                now: now,
                profile: smartColorProfile
            )
        }
        return themeColors.gaugeNSColor(for: Double(pct), thresholds: thresholds)
    }

    /// The colour of the amount an uncapped Extra Credits segment draws in
    /// place of its percentage: `labelColor` while nothing is spent, the
    /// theme's warning gauge colour once something is (the rule of the
    /// dashboard card, the popover and the widgets). Monochrome stays
    /// monochrome. Internal so the rule is unit-testable on its own.
    static func uncappedSpendColor(
        hasSpend: Bool,
        monochrome: Bool,
        themeColors: ThemeColors,
        thresholds: UsageThresholds
    ) -> NSColor {
        guard hasSpend, !monochrome else { return .labelColor }
        return themeColors.gaugeNSColor(for: Double(thresholds.warningPercent), thresholds: thresholds)
    }

    private static func colorForZone(_ zone: PacingZone, data: RenderData) -> NSColor {
        if data.menuBarMonochrome { return .labelColor }
        return data.themeColors.pacingNSColor(for: zone)
    }

    /// Default colour for the period label ("5h" / "7d") when the user has not
    /// picked a custom hex. Secondary (~55%) rather than tertiary (~26%) so the
    /// label stays legible on a *light* menu bar (the old tertiary grey was
    /// nearly invisible there) while still ranking below the bold, colour-coded
    /// value. The secondary default is @pulkitxm's fix from #197; #201 builds on
    /// it so a custom hex is also honored in monochrome (#196).
    static let defaultPeriodLabelColor: NSColor = .secondaryLabelColor

    /// Resolves the period-label colour. The user's custom hex wins in BOTH
    /// modes, including monochrome, so a monochrome user on a light menu bar can
    /// still tune the "5h" / "7d" label colour (#196). With no custom hex it
    /// falls back to the legible `defaultPeriodLabelColor`. Kept internal and
    /// `RenderData`-free so it is unit-testable in isolation.
    static func periodLabelColor(hex: String) -> NSColor {
        MenuBarTextColorResolver.resolve(hex: hex, fallback: defaultPeriodLabelColor)
    }

    private static func periodColor(_ data: RenderData) -> NSColor {
        periodLabelColor(hex: data.sessionPeriodColorHex)
    }

    /// Reset countdown text color. Honors the Themes setting priority:
    ///   1. monochrome: always system label;
    ///   2. smart mode: risk-based (green/orange/red) using the same 3
    ///      gauge colors so it visually agrees with the session ring;
    ///   3. static: user-picked hex, falling back to the system label.
    private static func resetValueColor(_ data: RenderData) -> NSColor {
        if data.menuBarMonochrome { return NSColor.labelColor }
        if data.smartResetColor {
            return data.themeColors.smartGaugeNSColor(
                utilization: Double(data.fiveHourPct),
                resetDate: data.fiveHourResetDate,
                windowDuration: 5 * 3600,
                thresholds: data.thresholds,
                pacingMargin: data.pacingMargin,
                profile: data.smartColorProfile
            )
        }
        return MenuBarTextColorResolver.resolve(
            hex: data.resetTextColorHex,
            fallback: .labelColor
        )
    }

    /// Thin wrapper kept for API compatibility with the existing tests.
    /// Delegates to the shared `ThemeColors.smartGaugeNSColor` so the menu
    /// bar reset color and the in-app smart gauges always stay in sync.
    /// `windowDuration` defaults to 5h since this helper is historically
    /// scoped to the 5-hour reset countdown.
    static func smartResetNSColor(
        utilization: Double,
        resetDate: Date,
        themeColors: ThemeColors,
        thresholds: UsageThresholds,
        windowDuration: TimeInterval = 5 * 3600,
        now: Date = Date()
    ) -> NSColor {
        themeColors.smartGaugeNSColor(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            now: now
        )
    }

    // MARK: - Outage badge

    /// Composite an outage glyph + mm:ss countdown ahead of the normal content.
    /// When usage data isn't usable (no config / usage error), show the badge
    /// alone, which avoids compositing a template logo into a coloured image.
    private static func renderWithOutageBadge(_ data: RenderData) -> NSImage {
        let badge = renderOutageBadgeImage(data)
        guard hasUsableMetrics(data) else { return badge }
        let base = drawComposition(data)
        // An empty / all-filtered composition draws the template logo, which
        // would composite as static black next to the coloured badge. Show the
        // badge alone in that case (an empty menu bar is a legitimate choice).
        guard !base.hitRects.isEmpty else { return badge }
        return horizontallyCompose(left: badge, right: base.image, gap: 5)
    }

    private static func renderOutageBadgeImage(_ data: RenderData) -> NSImage {
        let tint: NSColor = data.outageHealth == .down ? .systemRed : .systemOrange

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        let glyph = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        let glyphSize = glyph?.size ?? NSSize(width: 12, height: 12)

        var countdown: NSAttributedString?
        if let secs = data.nextPollSeconds {
            let clamped = max(0, secs)
            let text = String(format: "%d:%02d", clamped / 60, clamped % 60)
            countdown = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: tint,
            ])
        }

        let gap: CGFloat = 3
        let textWidth = countdown?.size().width ?? 0
        let width = glyphSize.width + (countdown != nil ? gap + textWidth : 0)
        let img = NSImage(size: NSSize(width: ceil(width) + 2, height: imageHeight), flipped: false) { _ in
            glyph?.draw(at: NSPoint(x: 1, y: (imageHeight - glyphSize.height) / 2),
                        from: .zero, operation: .sourceOver, fraction: 1)
            if let countdown {
                let ts = countdown.size()
                countdown.draw(at: NSPoint(x: 1 + glyphSize.width + gap, y: (imageHeight - ts.height) / 2))
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func horizontallyCompose(left: NSImage, right: NSImage, gap: CGFloat) -> NSImage {
        let width = left.size.width + gap + right.size.width
        let img = NSImage(size: NSSize(width: ceil(width), height: imageHeight), flipped: false) { _ in
            left.draw(at: NSPoint(x: 0, y: (imageHeight - left.size.height) / 2),
                      from: .zero, operation: .sourceOver, fraction: 1)
            right.draw(at: NSPoint(x: left.size.width + gap, y: (imageHeight - right.size.height) / 2),
                       from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: - Composition rendering

    private static let imageHeight: CGFloat = 22
    private static let segmentGap: CGFloat = 6
    private static let pillHeight: CGFloat = 17
    private static let pillPaddingH: CGFloat = 7
    private static let pillFont = NSFont.systemFont(ofSize: 11, weight: .bold)

    /// Space between an account's marker and the first segment it marks:
    /// tighter than between two segments, so the mark reads as part of the
    /// run it names rather than as a segment of its own.
    private static let markerGap: CGFloat = 3
    /// Space before a marker that follows something: wider than between two
    /// segments, so each account's run reads as one block and the previous
    /// run's last glyph (often a pacing dot) does not run into the next ring.
    private static let accountGap: CGFloat = 12
    /// The marker is a ring, not a disc: the pacing dots next to it are
    /// filled glyphs coloured by risk, and the account's mark must not read
    /// as one of them. As large as those dots and drawn thick enough for the
    /// colour to read on a non-Retina screen.
    private static let markerDot: CGFloat = 9
    private static let markerRingWidth: CGFloat = 2.5
    /// On a monochrome bar the ring carries no colour, the initial says
    /// which account it is: the ring shrinks back to a small mark so that,
    /// as large as a capital, it does not read as an "O" before the letter.
    private static let monochromeMarkerDot: CGFloat = 6
    private static let monochromeMarkerRingWidth: CGFloat = 1.5
    /// The monochrome initial sits close to its ring and is drawn as bright
    /// as the values, so "C" never reads as part of a dimmer period label
    /// after it.
    private static let initialGap: CGFloat = 2.5
    private static let markerFont = NSFont.systemFont(ofSize: 11, weight: .bold)

    private struct SegmentVisual {
        let id: UUID
        let content: Content
        enum Content {
            case run(NSAttributedString)
            case pill(text: String, tint: NSColor)
            /// An account's mark: its ring, then its initial on a monochrome bar.
            case marker(dot: NSColor, diameter: CGFloat, ring: CGFloat, name: NSAttributedString?)
        }

        var isMarker: Bool {
            if case .marker = content { return true }
            return false
        }
    }

    /// One drawable segment with the numbers it reads and the account whose
    /// run it belongs to (nil for Codex and the neutral kinds, which break a
    /// run).
    private struct PlannedSegment {
        let segment: MenuBarSegment
        let source: RenderData
        let account: String?
    }

    /// The visible segments that will draw, in order, each with its source.
    private static func plannedSegments(_ data: RenderData) -> [PlannedSegment] {
        let marksAccounts = !data.accountMarkers.isEmpty
        return data.composition.visibleSegments.compactMap { segment in
            guard var source = source(for: segment, data: data),
                  isSegmentAvailable(segment.kind, data: source) else { return nil }
            let account = segment.kind.provider == .claude ? accountKey(for: segment, data: data) : nil
            // With several accounts, one with no snapshot yet (or no login)
            // shows "--" in its run rather than a 0% or the bare logo.
            if marksAccounts, account != nil, !source.hasNumbers {
                source.showsPlaceholderValues = true
            }
            return PlannedSegment(segment: segment, source: source, account: account)
        }
    }

    /// What the bar draws, in order: a marker before each run of consecutive
    /// Claude segments of one account (the main account included) once the
    /// bar shows two accounts (or one in Claude mode), and every drawable
    /// segment. A Codex or neutral segment ends a run, so an account split
    /// around one is marked twice. With a single account there is no marker,
    /// and the plan is the segments alone.
    static func layoutPlan(_ data: RenderData) -> [PlannedVisual] {
        var plan: [PlannedVisual] = []
        var run: String?
        let planned = plannedSegments(data)
        let shownAccounts = Set(planned.compactMap(\.account))
        let marks = data.marksLoneAccount || shownAccounts.count >= 2
        for planned in planned {
            if marks, let account = planned.account, account != run, data.accountMarkers[account] != nil {
                plan.append(.marker(account))
            }
            run = planned.account
            plan.append(.segment(planned.segment.id))
        }
        return plan
    }

    /// Draws the visible, account-available segments left to right into a single
    /// image, mixing text runs and tinted pills, and returns per-segment hit
    /// rects. Falls back to the app logo when nothing is drawable, so the status
    /// item never collapses to an invisible sliver. An account marker belongs
    /// to the segment it precedes: clicking it selects that segment.
    private static func drawComposition(_ data: RenderData) -> (image: NSImage, hitRects: [SegmentHitRect]) {
        let segments = Dictionary(plannedSegments(data).map { ($0.segment.id, $0) }, uniquingKeysWith: { first, _ in first })
        let plan = layoutPlan(data)
        let initials = data.menuBarMonochrome ? monochromeInitials(plan: plan, data: data) : [:]
        let visuals: [SegmentVisual] = plan.compactMap { step in
            switch step {
            case .marker(let account):
                guard let marker = data.accountMarkers[account] else { return nil }
                return markerVisual(marker, initial: initials[account], data: data)
            case .segment(let id):
                guard let planned = segments[id] else { return nil }
                return visual(for: planned.segment, data: planned.source)
            }
        }
        guard visuals.contains(where: { !$0.isMarker }) else {
            return (renderLogoTemplate(), [])
        }

        let widths = visuals.map { visualWidth($0) }
        var gaps: [CGFloat] = []
        for (i, v) in visuals.enumerated() where i < visuals.count - 1 {
            gaps.append(v.isMarker ? markerGap : visuals[i + 1].isMarker ? accountGap : segmentGap)
        }
        let total = widths.reduce(0, +) + gaps.reduce(0, +)
        let imgSize = NSSize(width: ceil(total) + 2, height: imageHeight)

        var rects: [SegmentHitRect] = []
        var cursor: CGFloat = 1
        var markerStart: CGFloat?
        for (i, v) in visuals.enumerated() {
            if v.isMarker {
                markerStart = cursor
            } else {
                let start = markerStart ?? cursor
                rects.append(SegmentHitRect(
                    id: v.id,
                    rect: CGRect(x: start, y: 0, width: cursor + widths[i] - start, height: imageHeight)
                ))
                markerStart = nil
            }
            cursor += widths[i] + (i < gaps.count ? gaps[i] : 0)
        }

        let img = NSImage(size: imgSize, flipped: false) { _ in
            var x: CGFloat = 1
            for (i, v) in visuals.enumerated() {
                drawVisual(v, at: x, width: widths[i])
                x += widths[i] + (i < gaps.count ? gaps[i] : 0)
            }
            return true
        }
        img.isTemplate = false
        return (img, rects)
    }

    /// The initials a monochrome bar writes after its rings, worked out over
    /// the accounts the bar actually marks, in its order: an account kept
    /// out of the bar never lengthens another's.
    static func monochromeInitials(plan: [PlannedVisual], data: RenderData) -> [String: String] {
        var seen: Set<String> = []
        let marked: [(key: String, name: String)] = plan.compactMap { step in
            guard case .marker(let account) = step, seen.insert(account).inserted,
                  let marker = data.accountMarkers[account] else { return nil }
            return (account, marker.label)
        }
        return AccountNameRules.monochromeInitials(marked)
    }

    /// The full names of the accounts the bar marks, one per ring and in
    /// the bar's order (an account split around a Codex segment is named
    /// twice, as it is ringed twice), or nil when it marks none (a single
    /// account).
    static func accountsToolTip(_ data: RenderData) -> String? {
        var names: [String] = []
        for visual in layoutPlan(data) {
            guard case .marker(let account) = visual,
                  let marker = data.accountMarkers[account] else { continue }
            names.append(marker.label)
        }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    /// The account a Claude segment reads: the one it names, or the bar's
    /// default (the focused account in Claude mode, the main one otherwise).
    private static func accountKey(for segment: MenuBarSegment, data: RenderData) -> String {
        segment.account?.rawValue ?? data.defaultAccount
    }

    /// The numbers a segment reads: an added account's for a Claude segment
    /// that resolves to it, the bar's own otherwise. Nil when that account is
    /// not running, so the segment is skipped and the bar recompacts.
    static func source(for segment: MenuBarSegment, data: RenderData) -> RenderData? {
        guard segment.kind.provider == .claude else { return data }
        let account = accountKey(for: segment, data: data)
        guard account != AccountID.main.rawValue else { return data }
        return data.accountData[account]
    }

    /// The marker's visual: a ring in the account's colour and nothing else,
    /// so the bar stays free of names; the values after it keep their risk
    /// colours. A monochrome bar draws every ring alike, so there the ring
    /// is followed by the account's initial, the least text that still says
    /// which account a run belongs to.
    private static func markerVisual(_ marker: AccountMarker, initial: String?, data: RenderData) -> SegmentVisual {
        let name = data.menuBarMonochrome
            ? initial.map {
                NSAttributedString(string: $0, attributes: [
                    .font: markerFont, .foregroundColor: NSColor.labelColor,
                ])
            }
            : nil
        let mono = data.menuBarMonochrome
        return SegmentVisual(id: UUID(), content: .marker(
            dot: mono ? .labelColor : NSColor(hex: marker.colorHex),
            diameter: mono ? monochromeMarkerDot : markerDot,
            ring: mono ? monochromeMarkerRingWidth : markerRingWidth,
            name: name
        ))
    }

    /// Presence / data gating, matching the pre-5.10 renderer: metrics the
    /// account lacks, or session/pacing segments with no data yet, draw nothing
    /// and the row recompacts (falling back to the logo if all are filtered).
    private static func isSegmentAvailable(_ kind: MenuBarSegmentKind, data: RenderData) -> Bool {
        if let provider = kind.provider, !data.visibleProviders.contains(provider) { return false }
        switch kind {
        case .sonnet: return data.hasSonnet
        case .fable: return data.hasFable
        case .extraCredits: return data.hasExtraCredits
        // Pacing segments follow a 3-state model: absent (bucket missing) ->
        // drawn nothing; idle (bucket present, no active window yet) -> a muted
        // "-" placeholder from `pacingContent`; active -> shape + delta. So
        // availability here gates on the bucket's PRESENCE, and the window
        // check (`has*Pacing`) drives the placeholder in `pacingContent`.
        case .sessionReset, .sessionPacing: return data.hasFiveHourBucket
        case .fablePacing: return data.hasFable
        case .codexSession, .codexSessionPacing: return data.codexSession != nil
        case .codexWeekly, .codexWeeklyPacing: return data.codexWeekly != nil
        default: return true // weeklyPacing + non-gated kinds: present with config
        }
    }

    private static func visual(for segment: MenuBarSegment, data: RenderData) -> SegmentVisual? {
        let style = segment.effectiveStyle
        let content: SegmentVisual.Content?
        switch segment.kind.family {
        case .usage:
            content = usageContent(kind: segment.kind, style: style, data: data)
        case .pacing:
            content = pacingContent(kind: segment.kind, style: style, shape: segment.options.pacingShape, data: data)
        case .status:
            switch segment.kind {
            case .sessionReset: content = resetContent(style: style, format: segment.options.resetFormat, data: data)
            case .serviceStatus: content = statusContent(style: style, data: data)
            default: content = nil
            }
        }
        guard let content else { return nil }
        return SegmentVisual(id: segment.id, content: content)
    }

    // MARK: - Per-family content

    private static func usageContent(kind: MenuBarSegmentKind, style: MenuBarSegmentStyle, data: RenderData) -> SegmentVisual.Content {
        let value = usageValue(kind, data: data)
        let label = usageLabel(kind, data: data)
        // Extra Credits with no monthly limit: the amount spent stands where
        // the always-0 percentage would, in every style. With no limit there
        // is no threshold to measure against, so the colour follows the money
        // (`uncappedSpendColor`): neutral at zero, the warning gauge colour
        // once something is spent. Everything else, the capped pool included,
        // draws its percentage through the same path.
        if data.showsPlaceholderValues {
            return placeholderContent(kind: kind, style: style, data: data)
        }
        let spend = kind == .extraCredits ? data.extraCreditsUncappedSpend : nil
        let color = spend != nil
            ? uncappedSpendColor(
                hasSpend: data.extraCreditsUncappedHasSpend,
                monochrome: data.menuBarMonochrome,
                themeColors: data.themeColors,
                thresholds: data.thresholds
            )
            : colorForPct(value, resetDate: usageResetDate(kind, data: data), windowDuration: usageWindow(kind, data: data), data: data)
        let valueText = spend ?? "\(value)%"

        switch style {
        case .labelValue:
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: "\(label) ", attributes: [
                .font: systemFont(9, .medium), .foregroundColor: periodColor(data),
            ]))
            s.append(NSAttributedString(string: valueText, attributes: [
                .font: systemFont(12, .bold, monoDigits: true), .foregroundColor: color,
            ]))
            return .run(s)
        case .mono:
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: "\(label):", attributes: [
                .font: monoFont(11, .regular), .foregroundColor: periodColor(data),
            ]))
            s.append(NSAttributedString(string: spend ?? "\(value)", attributes: [
                .font: monoFont(11, .bold), .foregroundColor: color,
            ]))
            return .run(s)
        case .pill:
            return .pill(text: valueText, tint: color)
        default:
            // `.valueOnly` and any style this family does not special-case.
            return .run(NSAttributedString(string: valueText, attributes: [
                .font: systemFont(12, .bold, monoDigits: true), .foregroundColor: color,
            ]))
        }
    }

    /// A usage segment with no number yet: its label as usual and "--" in
    /// a muted colour, so it never passes for a real 0%.
    private static func placeholderContent(kind: MenuBarSegmentKind, style: MenuBarSegmentStyle, data: RenderData) -> SegmentVisual.Content {
        let label = usageLabel(kind, data: data)
        let muted = NSColor.tertiaryLabelColor
        switch style {
        case .labelValue:
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: "\(label) ", attributes: [
                .font: systemFont(9, .medium), .foregroundColor: periodColor(data),
            ]))
            s.append(NSAttributedString(string: "--", attributes: [
                .font: systemFont(12, .bold, monoDigits: true), .foregroundColor: muted,
            ]))
            return .run(s)
        case .mono:
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: "\(label):", attributes: [
                .font: monoFont(11, .regular), .foregroundColor: periodColor(data),
            ]))
            s.append(NSAttributedString(string: "--", attributes: [
                .font: monoFont(11, .bold), .foregroundColor: muted,
            ]))
            return .run(s)
        case .pill:
            return .pill(text: "--", tint: muted)
        default:
            return .run(NSAttributedString(string: "--", attributes: [
                .font: systemFont(12, .bold, monoDigits: true), .foregroundColor: muted,
            ]))
        }
    }

    private static func pacingContent(kind: MenuBarSegmentKind, style: MenuBarSegmentStyle, shape: PacingShape, data: RenderData) -> SegmentVisual.Content {
        // A pacing segment reaches here whenever its bucket is present
        // (isSegmentAvailable). `hasData` is whether there's an active window to
        // compute a pace against; when false the segment draws a muted "-"
        // placeholder (idle) rather than a bogus 0% delta.
        let hasData: Bool
        let zone: PacingZone
        let delta: Int
        switch kind {
        case .codexSessionPacing:
            hasData = data.codexSession?.hasPacing ?? false
            zone = data.codexSession?.pacingZone ?? .onTrack
            delta = data.codexSession?.pacingDelta ?? 0
        case .codexWeeklyPacing:
            hasData = data.codexWeekly?.hasPacing ?? false
            zone = data.codexWeekly?.pacingZone ?? .onTrack
            delta = data.codexWeekly?.pacingDelta ?? 0
        case .sessionPacing: hasData = data.hasSessionPacing; zone = data.sessionPacingZone; delta = data.sessionPacingDelta
        case .fablePacing:   hasData = data.hasFablePacing;   zone = data.fablePacingZone;   delta = data.fablePacingDelta
        default:             hasData = data.hasWeeklyPacing;  zone = data.weeklyPacingZone;  delta = data.weeklyPacingDelta
        }
        let tint = hasData ? colorForZone(zone, data: data) : NSColor.tertiaryLabelColor
        let sign = delta >= 0 ? "+" : ""
        let glyph = shape.glyph

        switch style {
        case .dot:
            return .run(NSAttributedString(string: glyph, attributes: [
                .font: systemFont(11, .bold), .foregroundColor: tint,
            ]))
        case .dotDelta:
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: glyph, attributes: [
                .font: systemFont(11, .bold), .foregroundColor: tint,
            ]))
            s.append(NSAttributedString(string: hasData ? " \(sign)\(delta)%" : " -", attributes: [
                .font: systemFont(10, .bold, monoDigits: true), .foregroundColor: tint,
            ]))
            return .run(s)
        case .delta:
            return .run(NSAttributedString(string: hasData ? "\(sign)\(delta)%" : "-", attributes: [
                .font: systemFont(10, .bold, monoDigits: true), .foregroundColor: tint,
            ]))
        case .pill:
            return .pill(text: hasData ? "\(glyph) \(sign)\(delta)%" : "\(glyph) -", tint: tint)
        default:
            return .run(NSAttributedString(string: hasData ? "\(sign)\(delta)%" : "-", attributes: [
                .font: systemFont(10, .bold, monoDigits: true), .foregroundColor: tint,
            ]))
        }
    }

    private static func resetContent(style: MenuBarSegmentStyle, format: ResetDisplayFormat, data: RenderData) -> SegmentVisual.Content {
        let resolved = resetDisplayText(format: format, data: data)
        // Empty only when `fiveHour.resetsAt` is nil (typically between two 5h
        // windows). Fall back to `-` so the segment stays visible.
        let text = resolved.isEmpty ? "-" : resolved
        let color = resetValueColor(data)
        switch style {
        case .pill:
            return .pill(text: text, tint: color)
        default:
            return .run(NSAttributedString(string: text, attributes: [
                .font: systemFont(12, .bold, monoDigits: true), .foregroundColor: color,
            ]))
        }
    }

    private static func statusContent(style: MenuBarSegmentStyle, data: RenderData) -> SegmentVisual.Content {
        let mono = data.menuBarMonochrome
        let color: NSColor = {
            switch data.outageHealth {
            case .healthy:  return mono ? .labelColor : .systemGreen
            case .degraded: return mono ? .labelColor : .systemOrange
            case .down:     return mono ? .labelColor : .systemRed
            }
        }()

        if style == .pill {
            let text: String
            switch data.outageHealth {
            case .healthy: text = "OK"
            case .degraded: text = "!"
            case .down:
                if let secs = data.nextPollSeconds {
                    let c = max(0, secs)
                    text = String(format: "%d:%02d", c / 60, c % 60)
                } else {
                    text = "!"
                }
            }
            return .pill(text: text, tint: color)
        }

        // glyph style
        let symbolName = data.outageHealth == .healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        let s = NSMutableAttributedString()
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        if let glyph = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let attachment = NSTextAttachment()
            attachment.image = glyph
            attachment.bounds = CGRect(x: 0, y: (11 - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height)
            s.append(NSAttributedString(attachment: attachment))
        }
        if data.outageHealth == .down, let secs = data.nextPollSeconds {
            let c = max(0, secs)
            s.append(NSAttributedString(string: String(format: " %d:%02d", c / 60, c % 60), attributes: [
                .font: systemFont(11, .semibold, monoDigits: true), .foregroundColor: color,
            ]))
        }
        return .run(s)
    }

    // MARK: - Metric value lookups

    private static func usageValue(_ kind: MenuBarSegmentKind, data: RenderData) -> Int {
        switch kind {
        case .session: return data.fiveHourPct
        case .weekly: return data.sevenDayPct
        case .sonnet: return data.sonnetPct
        case .fable: return data.fablePct
        case .extraCredits: return data.extraCreditsPct
        case .codexSession: return data.codexSession?.pct ?? 0
        case .codexWeekly: return data.codexWeekly?.pct ?? 0
        default: return 0
        }
    }

    private static func usageLabel(_ kind: MenuBarSegmentKind, data: RenderData) -> String {
        switch kind {
        case .session: return MetricID.fiveHour.shortLabel
        case .weekly: return MetricID.sevenDay.shortLabel
        case .sonnet: return MetricID.sonnet.shortLabel
        case .fable: return MetricID.fable.shortLabel
        case .extraCredits: return MetricID.extraCredits.shortLabel
        // "CX" / "CXW" named the provider, not the window, so the menu bar
        // went from "5h 68%" to "CX 41%" for two windows of the same length.
        // The label describes the window; it is derived from the duration the
        // payload declares rather than assumed, so a Codex plan with a window
        // this app has never seen still gets an honest label instead of a
        // hardcoded one.
        case .codexSession, .codexWeekly:
            return durationShortLabel(usageWindow(kind, data: data))

        default: return ""
        }
    }

    /// "5h", "7d", and something sensible for a length this app has not met.
    /// Matches `MetricID.shortLabel` for the two windows Claude has, which is
    /// the whole point: the label names the window, not who it belongs to.
    static func durationShortLabel(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "" }
        let hours = Int((seconds / 3600).rounded())
        if hours < 48 { return "\(hours)h" }
        return "\(Int((seconds / 86_400).rounded()))d"
    }

    private static func usageResetDate(_ kind: MenuBarSegmentKind, data: RenderData) -> Date? {
        switch kind {
        case .session: return data.fiveHourResetDate
        case .weekly: return data.sevenDayResetDate
        case .sonnet: return data.sonnetResetDate
        case .fable: return data.fableResetDate
        case .codexSession: return data.codexSession?.resetDate
        case .codexWeekly: return data.codexWeekly?.resetDate
        default: return nil  // extraCredits: no reset window -> static threshold
        }
    }

    private static func usageWindow(_ kind: MenuBarSegmentKind, data: RenderData) -> TimeInterval {
        switch kind {
        case .session: return 5 * 3600
        case .weekly, .sonnet, .fable: return 7 * 86_400
        // Server-declared, not assumed: a Codex plan can carry a window length
        // this app has never seen, and Smart Color only needs the number.
        case .codexSession: return data.codexSession?.windowDuration ?? 0
        case .codexWeekly: return data.codexWeekly?.windowDuration ?? 0
        default: return 0  // extraCredits: windowless
        }
    }

    private static func resetDisplayText(format: ResetDisplayFormat, data: RenderData) -> String {
        let relative = data.fiveHourReset
        let absolute = data.fiveHourResetAbsolute
        switch format {
        case .relative: return relative
        case .absolute: return absolute
        case .both:
            if relative.isEmpty { return absolute }
            if absolute.isEmpty { return relative }
            return "\(relative) - \(absolute)"
        }
    }

    // MARK: - Layout primitives

    private static func systemFont(_ size: CGFloat, _ weight: NSFont.Weight, monoDigits: Bool = false) -> NSFont {
        monoDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
    }

    private static func monoFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func visualWidth(_ v: SegmentVisual) -> CGFloat {
        switch v.content {
        case .run(let s):
            return max(ceil(s.size().width), 1)
        case .pill(let text, _):
            let w = (text as NSString).size(withAttributes: [.font: pillFont]).width
            return ceil(w) + pillPaddingH * 2
        case .marker(_, let diameter, _, let name):
            guard let name else { return diameter }
            return diameter + initialGap + ceil(name.size().width)
        }
    }

    private static func drawVisual(_ v: SegmentVisual, at x: CGFloat, width: CGFloat) {
        switch v.content {
        case .run(let s):
            let sz = s.size()
            s.draw(at: NSPoint(x: x, y: (imageHeight - sz.height) / 2))
        case .pill(let text, let tint):
            let rect = NSRect(x: x, y: (imageHeight - pillHeight) / 2, width: width, height: pillHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
            tint.withAlphaComponent(0.18).setFill()
            path.fill()
            tint.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 0.8
            path.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: pillFont, .foregroundColor: tint]
            let ts = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(
                at: NSPoint(x: x + (width - ts.width) / 2, y: (imageHeight - ts.height) / 2 - 0.5),
                withAttributes: attrs
            )
        case .marker(let dot, let diameter, let ringWidth, let name):
            let inset = ringWidth / 2
            let dotRect = NSRect(x: x, y: (imageHeight - diameter) / 2, width: diameter, height: diameter)
                .insetBy(dx: inset, dy: inset)
            dot.setStroke()
            let ring = NSBezierPath(ovalIn: dotRect)
            ring.lineWidth = ringWidth
            ring.stroke()
            if let name {
                let ts = name.size()
                name.draw(at: NSPoint(x: x + diameter + initialGap, y: (imageHeight - ts.height) / 2))
            }
        }
    }

    /// App logo silhouette for menu bar (template - macOS renders white/black automatically).
    private static func renderLogoTemplate() -> NSImage {
        let s: CGFloat = 16
        let height: CGFloat = 22
        let imgSize = NSSize(width: s + 2, height: height)
        let scale = s / 300.0
        let yOff = (height - s) / 2

        let img = NSImage(size: imgSize, flipped: true) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.translateBy(x: 1, y: yOff)
            ctx.scaleBy(x: scale, y: scale)

            NSColor.black.setFill()

            let lPath = CGMutablePath()
            let r: CGFloat = 32
            lPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: 300, height: 122), cornerWidth: r, cornerHeight: r)
            lPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: 122, height: 300), cornerWidth: r, cornerHeight: r)
            ctx.addPath(lPath)
            ctx.fillPath(using: .winding)

            let bar1 = CGRect(x: 142, y: 142, width: 158, height: 70)
            let bar2 = CGRect(x: 142, y: 230, width: 158, height: 70)
            let barR: CGFloat = 24
            ctx.addPath(CGPath(roundedRect: bar1, cornerWidth: barR, cornerHeight: barR, transform: nil))
            ctx.fillPath()
            ctx.addPath(CGPath(roundedRect: bar2, cornerWidth: barR, cornerHeight: barR, transform: nil))
            ctx.fillPath()

            return true
        }
        img.isTemplate = true
        return img
    }
}

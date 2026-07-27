import AppKit

enum MenuBarRenderer {
    struct RenderData: Equatable {
        /// The composable menu bar: ordered segments + per-segment styles.
        /// Drives which segments appear, in what order, and how each is drawn.
        let composition: MenuBarComposition
        let fiveHourPct: Int
        let sevenDayPct: Int
        let sonnetPct: Int
        let weeklyPacingDelta: Int
        let weeklyPacingZone: PacingZone
        let hasWeeklyPacing: Bool
        let sessionPacingDelta: Int
        let sessionPacingZone: PacingZone
        let hasSessionPacing: Bool
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
        let designResetDate: Date?
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
        let designPct: Int
        let hasDesign: Bool
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
        if !data.hasConfig || (data.hasError && !data.isAwaitingRefresh) {
            return renderLogoTemplate()
        }
        return drawComposition(data).image
    }

    /// Composition render that also returns each segment's hit rectangle in the
    /// image's coordinate space. The status item ignores the rects; the editor
    /// preview overlays invisible tap targets from them (click-to-select).
    /// Mirrors `renderUncached`'s top-level dispatch so the preview matches the
    /// real item, but never composes the separate outage badge (the preview is
    /// about the composition itself).
    static func renderWithHitRects(_ data: RenderData) -> (image: NSImage, hitRects: [SegmentHitRect]) {
        if !data.hasConfig || (data.hasError && !data.isAwaitingRefresh) {
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
    /// popover, the dashboard and the widgets. Internal (not private) so the
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
    /// alone — avoids compositing a template logo into a coloured image.
    private static func renderWithOutageBadge(_ data: RenderData) -> NSImage {
        let badge = renderOutageBadgeImage(data)
        let hasMetrics = data.hasConfig && (!data.hasError || data.isAwaitingRefresh)
        guard hasMetrics else { return badge }
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

    private struct SegmentVisual {
        let id: UUID
        let content: Content
        enum Content {
            case run(NSAttributedString)
            case pill(text: String, tint: NSColor)
        }
    }

    /// Draws the visible, account-available segments left to right into a single
    /// image, mixing text runs and tinted pills, and returns per-segment hit
    /// rects. Falls back to the app logo when nothing is drawable, so the status
    /// item never collapses to an invisible sliver.
    private static func drawComposition(_ data: RenderData) -> (image: NSImage, hitRects: [SegmentHitRect]) {
        let visuals: [SegmentVisual] = data.composition.visibleSegments.compactMap { segment in
            guard isSegmentAvailable(segment.kind, data: data) else { return nil }
            return visual(for: segment, data: data)
        }
        guard !visuals.isEmpty else {
            return (renderLogoTemplate(), [])
        }

        let widths = visuals.map { visualWidth($0) }
        let total = widths.reduce(0, +) + segmentGap * CGFloat(max(visuals.count - 1, 0))
        let imgSize = NSSize(width: ceil(total) + 2, height: imageHeight)

        var rects: [SegmentHitRect] = []
        var cursor: CGFloat = 1
        for (i, v) in visuals.enumerated() {
            rects.append(SegmentHitRect(id: v.id, rect: CGRect(x: cursor, y: 0, width: widths[i], height: imageHeight)))
            cursor += widths[i] + segmentGap
        }

        let img = NSImage(size: imgSize, flipped: false) { _ in
            var x: CGFloat = 1
            for (i, v) in visuals.enumerated() {
                drawVisual(v, at: x, width: widths[i])
                x += widths[i] + segmentGap
            }
            return true
        }
        img.isTemplate = false
        return (img, rects)
    }

    /// Presence / data gating, matching the pre-5.10 renderer: metrics the
    /// account lacks, or session/pacing segments with no data yet, draw nothing
    /// and the row recompacts (falling back to the logo if all are filtered).
    private static func isSegmentAvailable(_ kind: MenuBarSegmentKind, data: RenderData) -> Bool {
        switch kind {
        case .design: return data.hasDesign
        case .fable: return data.hasFable
        case .extraCredits: return data.hasExtraCredits
        case .sessionReset, .sessionPacing: return data.hasFiveHourBucket
        case .weeklyPacing: return data.hasWeeklyPacing
        default: return true
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
        let label = usageLabel(kind)
        let color = colorForPct(value, resetDate: usageResetDate(kind, data: data), windowDuration: usageWindow(kind), data: data)

        switch style {
        case .labelValue:
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: "\(label) ", attributes: [
                .font: systemFont(9, .medium), .foregroundColor: periodColor(data),
            ]))
            s.append(NSAttributedString(string: "\(value)%", attributes: [
                .font: systemFont(12, .bold, monoDigits: true), .foregroundColor: color,
            ]))
            return .run(s)
        case .valueOnly:
            return .run(NSAttributedString(string: "\(value)%", attributes: [
                .font: systemFont(12, .bold, monoDigits: true), .foregroundColor: color,
            ]))
        case .mono:
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: "\(label):", attributes: [
                .font: monoFont(11, .regular), .foregroundColor: periodColor(data),
            ]))
            s.append(NSAttributedString(string: "\(value)", attributes: [
                .font: monoFont(11, .bold), .foregroundColor: color,
            ]))
            return .run(s)
        case .pill:
            return .pill(text: "\(value)%", tint: color)
        default:
            return .run(NSAttributedString(string: "\(value)%", attributes: [
                .font: systemFont(12, .bold, monoDigits: true), .foregroundColor: color,
            ]))
        }
    }

    private static func pacingContent(kind: MenuBarSegmentKind, style: MenuBarSegmentStyle, shape: PacingShape, data: RenderData) -> SegmentVisual.Content {
        // weeklyPacing only renders when hasWeeklyPacing (isSegmentAvailable),
        // so treat it as always having data here; session may show a placeholder.
        let hasData = kind == .sessionPacing ? data.hasSessionPacing : true
        let zone = kind == .sessionPacing ? data.sessionPacingZone : data.weeklyPacingZone
        let delta = kind == .sessionPacing ? data.sessionPacingDelta : data.weeklyPacingDelta
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
        case .design: return data.designPct
        case .fable: return data.fablePct
        case .extraCredits: return data.extraCreditsPct
        default: return 0
        }
    }

    private static func usageLabel(_ kind: MenuBarSegmentKind) -> String {
        switch kind {
        case .session: return MetricID.fiveHour.shortLabel
        case .weekly: return MetricID.sevenDay.shortLabel
        case .sonnet: return MetricID.sonnet.shortLabel
        case .design: return MetricID.design.shortLabel
        case .fable: return MetricID.fable.shortLabel
        case .extraCredits: return MetricID.extraCredits.shortLabel
        default: return ""
        }
    }

    private static func usageResetDate(_ kind: MenuBarSegmentKind, data: RenderData) -> Date? {
        switch kind {
        case .session: return data.fiveHourResetDate
        case .weekly: return data.sevenDayResetDate
        case .sonnet: return data.sonnetResetDate
        case .design: return data.designResetDate
        case .fable: return data.fableResetDate
        default: return nil  // extraCredits: no reset window -> static threshold
        }
    }

    private static func usageWindow(_ kind: MenuBarSegmentKind) -> TimeInterval {
        switch kind {
        case .session: return 5 * 3600
        case .weekly, .sonnet, .design, .fable: return 7 * 86_400
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

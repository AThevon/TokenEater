import AppKit

enum MenuBarRenderer {
    struct RenderData: Equatable {
        let pinnedMetrics: Set<MetricID>
        let displaySonnet: Bool
        let fiveHourPct: Int
        let sevenDayPct: Int
        let sonnetPct: Int
        let weeklyPacingDelta: Int
        let weeklyPacingZone: PacingZone
        let hasWeeklyPacing: Bool
        let sessionPacingDelta: Int
        let sessionPacingZone: PacingZone
        let hasSessionPacing: Bool
        let sessionPacingDisplayMode: PacingDisplayMode
        let weeklyPacingDisplayMode: PacingDisplayMode
        let hasConfig: Bool
        let hasError: Bool
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
        /// two 5h windows. Used to keep session pins visible (with a placeholder
        /// value) instead of making them disappear whenever there's a lull.
        let hasFiveHourBucket: Bool
        let resetDisplayFormat: ResetDisplayFormat
        let resetTextColorHex: String
        let sessionPeriodColorHex: String
        let smartResetColor: Bool
        let smartColorProfile: SmartColorProfile
        let pacingMargin: Double
        let menuBarStyle: MenuBarStyle
        let pacingShape: PacingShape
        let designPct: Int
        let hasDesign: Bool
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
        if !data.hasConfig || data.hasError {
            return renderLogoTemplate()
        }
        return renderPinnedMetrics(data)
    }

    // MARK: - Color helpers

    private static func colorForPct(_ pct: Int, resetDate: Date?, windowDuration: TimeInterval, data: RenderData) -> NSColor {
        if data.menuBarMonochrome { return .labelColor }
        if data.smartResetColor {
            return data.themeColors.smartGaugeNSColor(
                utilization: Double(pct),
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: data.thresholds,
                pacingMargin: data.pacingMargin,
                profile: data.smartColorProfile
            )
        }
        return data.themeColors.gaugeNSColor(for: Double(pct), thresholds: data.thresholds)
    }

    private static func resetDate(for metric: MetricID, data: RenderData) -> Date? {
        switch metric {
        case .fiveHour:    return data.fiveHourResetDate
        case .sevenDay:    return data.sevenDayResetDate
        case .sonnet:      return data.sonnetResetDate
        case .design:      return data.designResetDate
        default:           return nil
        }
    }

    private static func windowDuration(for metric: MetricID) -> TimeInterval {
        switch metric {
        case .fiveHour: return 5 * 3600
        case .sevenDay, .sonnet, .design: return 7 * 86_400
        default: return 0
        }
    }

    private static func colorForZone(_ zone: PacingZone, data: RenderData) -> NSColor {
        if data.menuBarMonochrome { return .labelColor }
        return data.themeColors.pacingNSColor(for: zone)
    }

    private static func periodColor(_ data: RenderData) -> NSColor {
        data.menuBarMonochrome
            ? NSColor.tertiaryLabelColor
            : MenuBarTextColorResolver.resolve(
                hex: data.sessionPeriodColorHex,
                fallback: .tertiaryLabelColor
            )
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

    // MARK: - Rendering

    private static func renderPinnedMetrics(_ data: RenderData) -> NSImage {
        // Minimal uses an entirely different drawing path (pills), so hand
        // off early instead of trying to fit it into the classic/mono
        // NSAttributedString pipeline.
        if data.menuBarStyle == .badge {
            return renderBadgePills(data)
        }

        let height: CGFloat = 22
        let str = NSMutableAttributedString()

        let sepAttrs: [NSAttributedString.Key: Any] = [
            .font: styleFont(size: 10, weight: .regular, style: data.menuBarStyle),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let separator: String = {
            switch data.menuBarStyle {
            case .classic: return "  "
            case .mono:    return " "
            case .badge: return " \u{00B7} "  // middle dot with spaces
            }
        }()

        let ordered: [MetricID] = [
            .sessionReset, .fiveHour, .sessionPacing, .sevenDay, .weeklyPacing, .sonnet, .design
        ].filter {
            guard data.pinnedMetrics.contains($0) else { return false }
            // Sonnet / Design visibility in the menu bar is purely driven
            // by pinnedMetrics. Popover visibility has its own toggles.
            if $0 == .design && !data.hasDesign { return false }
            switch $0 {
            // Session-scoped pins stay visible as long as the API returned a
            // five_hour bucket. Between sessions Anthropic omits resets_at, so
            // we render a neutral placeholder rather than silently hiding a
            // pin the user explicitly asked for.
            case .sessionReset, .sessionPacing: return data.hasFiveHourBucket
            case .weeklyPacing: return data.hasWeeklyPacing
            case .design: return data.hasDesign
            default: return true
            }
        }

        // If every pin got filtered out (no five-hour bucket yet, no weekly
        // pacing, no design quota), fall back to the logo so the status item
        // is always visible. Returning the empty-pipeline image produces a
        // 2pt-wide icon that reads as "the menu bar item disappeared".
        if ordered.isEmpty {
            return renderLogoTemplate()
        }
        for (i, metric) in ordered.enumerated() {
            if i > 0 {
                str.append(NSAttributedString(string: separator, attributes: sepAttrs))
            }
            switch metric {
            case .sessionReset:
                appendSessionReset(to: str, data: data)
            case .sessionPacing:
                if data.hasSessionPacing {
                    appendPacing(
                        to: str,
                        delta: data.sessionPacingDelta,
                        zone: data.sessionPacingZone,
                        mode: data.sessionPacingDisplayMode,
                        data: data
                    )
                } else {
                    appendPacingPlaceholder(
                        to: str,
                        mode: data.sessionPacingDisplayMode,
                        data: data
                    )
                }
            case .weeklyPacing:
                appendPacing(
                    to: str,
                    delta: data.weeklyPacingDelta,
                    zone: data.weeklyPacingZone,
                    mode: data.weeklyPacingDisplayMode,
                    data: data
                )
            case .fiveHour, .sevenDay, .sonnet, .design:
                let value: Int
                switch metric {
                case .fiveHour: value = data.fiveHourPct
                case .sevenDay: value = data.sevenDayPct
                case .sonnet: value = data.sonnetPct
                case .design: value = data.designPct
                default: value = 0
                }
                appendPercentMetric(
                    to: str,
                    label: metric.shortLabel,
                    value: value,
                    resetDate: resetDate(for: metric, data: data),
                    windowDuration: windowDuration(for: metric),
                    data: data
                )
            }
        }

        let size = str.size()
        let imgSize = NSSize(width: ceil(size.width) + 2, height: height)
        let img = NSImage(size: imgSize, flipped: false) { _ in
            str.draw(at: NSPoint(x: 1, y: (height - size.height) / 2))
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func appendSessionReset(to str: NSMutableAttributedString, data: RenderData) {
        let resolvedText = resetDisplayText(data: data)
        // Empty only when `fiveHour.resetsAt` is nil - typically between two
        // 5h windows. Fall back to an em-less `-` placeholder so the pin
        // stays visible and the user knows it's still active.
        let text = resolvedText.isEmpty ? "-" : resolvedText
        let attrs: [NSAttributedString.Key: Any] = [
            .font: styleFont(size: 12, weight: .bold, style: data.menuBarStyle, monospacedDigits: true),
            .foregroundColor: resetValueColor(data),
        ]
        str.append(NSAttributedString(string: text, attributes: attrs))
    }

    // MARK: - Badge pill rendering

    /// Badge style: each metric becomes a small rounded pill with a tinted
    /// background and colour-matched text. Drawn directly with NSBezierPath
    /// rather than NSAttributedString so we can get real rounded corners in
    /// the menu bar icon.
    private struct BadgePill {
        let text: String
        let tint: NSColor
    }

    private static func renderBadgePills(_ data: RenderData) -> NSImage {
        let pills = buildBadgePills(data)
        let height: CGFloat = 22
        let pillHeight: CGFloat = 17
        let paddingH: CGFloat = 7
        let gap: CGFloat = 5

        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font]

        let widths: [CGFloat] = pills.map { pill in
            ceil((pill.text as NSString).size(withAttributes: textAttrs).width) + paddingH * 2
        }
        let totalWidth = widths.reduce(0, +) + CGFloat(max(pills.count - 1, 0)) * gap
        guard totalWidth > 0 else {
            return NSImage(size: NSSize(width: 1, height: height))
        }

        let imgSize = NSSize(width: ceil(totalWidth) + 2, height: height)
        let img = NSImage(size: imgSize, flipped: false) { _ in
            var x: CGFloat = 1
            for (i, pill) in pills.enumerated() {
                let w = widths[i]
                let pillRect = NSRect(
                    x: x,
                    y: (height - pillHeight) / 2,
                    width: w,
                    height: pillHeight
                )
                let path = NSBezierPath(
                    roundedRect: pillRect,
                    xRadius: pillHeight / 2,
                    yRadius: pillHeight / 2
                )
                // Tinted fill (15% opacity) with a 1px outline of the same
                // colour at higher opacity - keeps the pill readable on both
                // light and dark menu bars.
                pill.tint.withAlphaComponent(0.18).setFill()
                path.fill()
                pill.tint.withAlphaComponent(0.55).setStroke()
                path.lineWidth = 0.8
                path.stroke()

                // Text centred.
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: pill.tint,
                ]
                let textSize = (pill.text as NSString).size(withAttributes: attrs)
                let textOrigin = NSPoint(
                    x: x + (w - textSize.width) / 2,
                    y: (height - textSize.height) / 2 - 0.5
                )
                (pill.text as NSString).draw(at: textOrigin, withAttributes: attrs)

                x += w + gap
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func buildBadgePills(_ data: RenderData) -> [BadgePill] {
        let ordered: [MetricID] = [
            .sessionReset, .fiveHour, .sessionPacing, .sevenDay, .weeklyPacing, .sonnet, .design
        ].filter {
            guard data.pinnedMetrics.contains($0) else { return false }
            // Sonnet / Design visibility in the menu bar is purely driven
            // by pinnedMetrics. Popover visibility has its own toggles.
            if $0 == .design && !data.hasDesign { return false }
            switch $0 {
            case .sessionReset, .sessionPacing: return data.hasFiveHourBucket
            case .weeklyPacing: return data.hasWeeklyPacing
            case .design: return data.hasDesign
            default: return true
            }
        }

        return ordered.compactMap { metric -> BadgePill? in
            switch metric {
            case .sessionReset:
                let text = resetDisplayText(data: data)
                return BadgePill(
                    text: text.isEmpty ? "-" : text,
                    tint: resetValueColor(data)
                )
            case .fiveHour:
                return BadgePill(
                    text: "\(data.fiveHourPct)%",
                    tint: colorForPct(data.fiveHourPct, resetDate: data.fiveHourResetDate, windowDuration: 5 * 3600, data: data)
                )
            case .sevenDay:
                return BadgePill(
                    text: "\(data.sevenDayPct)%",
                    tint: colorForPct(data.sevenDayPct, resetDate: data.sevenDayResetDate, windowDuration: 7 * 86_400, data: data)
                )
            case .sonnet:
                return BadgePill(
                    text: "\(data.sonnetPct)%",
                    tint: colorForPct(data.sonnetPct, resetDate: data.sonnetResetDate, windowDuration: 7 * 86_400, data: data)
                )
            case .design:
                return BadgePill(
                    text: "\(data.designPct)%",
                    tint: colorForPct(data.designPct, resetDate: data.designResetDate, windowDuration: 7 * 86_400, data: data)
                )
            case .sessionPacing:
                return pacingBadgePill(
                    hasData: data.hasSessionPacing,
                    zone: data.sessionPacingZone,
                    delta: data.sessionPacingDelta,
                    mode: data.sessionPacingDisplayMode,
                    data: data
                )
            case .weeklyPacing:
                return pacingBadgePill(
                    hasData: true,
                    zone: data.weeklyPacingZone,
                    delta: data.weeklyPacingDelta,
                    mode: data.weeklyPacingDisplayMode,
                    data: data
                )
            }
        }
    }

    /// Badge pacing pill content varies with `PacingDisplayMode`:
    /// dot-only, delta-only, or dot + delta. Also handles the placeholder
    /// state when we don't have a pacing result yet.
    private static func pacingBadgePill(
        hasData: Bool,
        zone: PacingZone,
        delta: Int,
        mode: PacingDisplayMode,
        data: RenderData
    ) -> BadgePill {
        let tint = hasData ? colorForZone(zone, data: data) : NSColor.tertiaryLabelColor
        let sign = delta >= 0 ? "+" : ""
        let shape = data.pacingShape.glyph
        let text: String = {
            switch mode {
            case .dot:      return shape
            case .dotDelta: return hasData ? "\(shape) \(sign)\(delta)%" : "\(shape) -"
            case .delta:    return hasData ? "\(sign)\(delta)%" : "-"
            }
        }()
        return BadgePill(text: text, tint: tint)
    }

    // MARK: - Style-aware helpers

    /// Font factory that adapts to `MenuBarStyle`:
    /// - classic: system font
    /// - mono: full monospaced system font
    /// - badge: rounded design (used behind pill text)
    /// `monospacedDigits` forces tabular-nums on the classic and minimal styles
    /// so percentages don't jitter as they change width.
    private static func styleFont(
        size: CGFloat,
        weight: NSFont.Weight,
        style: MenuBarStyle,
        monospacedDigits: Bool = false
    ) -> NSFont {
        switch style {
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .badge:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            let rounded = NSFontDescriptor(
                fontAttributes: [.family: "SF Pro Rounded"]
            )
            if let custom = NSFont(descriptor: rounded, size: size) {
                return monospacedDigits
                    ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                    : custom
            }
            return base
        case .classic:
            return monospacedDigits
                ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                : NSFont.systemFont(ofSize: size, weight: weight)
        }
    }

    /// Renders a `label + value%` block with style-specific layout:
    /// - classic: "5h 26%" (label tinted tertiary, value bold colored)
    /// - mono: "5h:26" (all mono, colon separator, no %)
    /// - minimal: "26%" (rounded font, no label)
    private static func appendPercentMetric(
        to str: NSMutableAttributedString,
        label: String,
        value: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        data: RenderData
    ) {
        let valueColor = colorForPct(value, resetDate: resetDate, windowDuration: windowDuration, data: data)

        switch data.menuBarStyle {
        case .classic:
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: styleFont(size: 9, weight: .medium, style: .classic),
                .foregroundColor: periodColor(data),
            ]
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: styleFont(size: 12, weight: .bold, style: .classic, monospacedDigits: true),
                .foregroundColor: valueColor,
            ]
            str.append(NSAttributedString(string: "\(label) ", attributes: labelAttrs))
            str.append(NSAttributedString(string: "\(value)%", attributes: valueAttrs))

        case .mono:
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: styleFont(size: 11, weight: .regular, style: .mono),
                .foregroundColor: periodColor(data),
            ]
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: styleFont(size: 11, weight: .bold, style: .mono),
                .foregroundColor: valueColor,
            ]
            str.append(NSAttributedString(string: "\(label):", attributes: labelAttrs))
            str.append(NSAttributedString(string: "\(value)", attributes: valueAttrs))

        case .badge:
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: styleFont(size: 13, weight: .bold, style: .badge, monospacedDigits: true),
                .foregroundColor: valueColor,
            ]
            str.append(NSAttributedString(string: "\(value)%", attributes: valueAttrs))
        }
    }

    private static func resetDisplayText(data: RenderData) -> String {
        let relative = data.fiveHourReset
        let absolute = data.fiveHourResetAbsolute
        switch data.resetDisplayFormat {
        case .relative:
            return relative
        case .absolute:
            return absolute
        case .both:
            if relative.isEmpty { return absolute }
            if absolute.isEmpty { return relative }
            return "\(relative) - \(absolute)"
        }
    }

    private static func appendPacing(
        to str: NSMutableAttributedString,
        delta: Int,
        zone: PacingZone,
        mode: PacingDisplayMode,
        data: RenderData
    ) {
        let dotColor = colorForZone(zone, data: data)
        let dotAttrs: [NSAttributedString.Key: Any] = [
            .font: styleFont(size: 11, weight: .bold, style: data.menuBarStyle),
            .foregroundColor: dotColor,
        ]
        let deltaAttrs: [NSAttributedString.Key: Any] = [
            .font: styleFont(size: 10, weight: .bold, style: data.menuBarStyle, monospacedDigits: true),
            .foregroundColor: dotColor,
        ]
        let sign = delta >= 0 ? "+" : ""
        switch mode {
        case .dot:
            str.append(NSAttributedString(string: data.pacingShape.glyph, attributes: dotAttrs))
        case .dotDelta:
            str.append(NSAttributedString(string: data.pacingShape.glyph, attributes: dotAttrs))
            str.append(NSAttributedString(string: " \(sign)\(delta)%", attributes: deltaAttrs))
        case .delta:
            str.append(NSAttributedString(string: "\(sign)\(delta)%", attributes: deltaAttrs))
        }
    }

    /// Neutral placeholder used when the pacing bucket exists but `resets_at`
    /// is missing, so we can't compute a meaningful delta. Uses the system's
    /// tertiary label colour to signal "data pending" without faking an
    /// on-track state.
    private static func appendPacingPlaceholder(
        to str: NSMutableAttributedString,
        mode: PacingDisplayMode,
        data: RenderData
    ) {
        let neutralColor: NSColor = .tertiaryLabelColor
        let dotAttrs: [NSAttributedString.Key: Any] = [
            .font: styleFont(size: 11, weight: .bold, style: data.menuBarStyle),
            .foregroundColor: neutralColor,
        ]
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: styleFont(size: 10, weight: .bold, style: data.menuBarStyle, monospacedDigits: true),
            .foregroundColor: neutralColor,
        ]
        switch mode {
        case .dot:
            str.append(NSAttributedString(string: data.pacingShape.glyph, attributes: dotAttrs))
        case .dotDelta:
            str.append(NSAttributedString(string: data.pacingShape.glyph, attributes: dotAttrs))
            str.append(NSAttributedString(string: " -", attributes: textAttrs))
        case .delta:
            str.append(NSAttributedString(string: "-", attributes: textAttrs))
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

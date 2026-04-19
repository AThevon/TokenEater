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

    private static func colorForPct(_ pct: Int, data: RenderData) -> NSColor {
        if data.menuBarMonochrome { return .labelColor }
        return data.themeColors.gaugeNSColor(for: Double(pct), thresholds: data.thresholds)
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
        if data.smartResetColor, let reset = data.fiveHourResetDate {
            return smartResetNSColor(
                utilization: Double(data.fiveHourPct),
                resetDate: reset,
                themeColors: data.themeColors
            )
        }
        return MenuBarTextColorResolver.resolve(
            hex: data.resetTextColorHex,
            fallback: .labelColor
        )
    }

    /// Risk = utilization * remaining_minutes / 100. Thresholds mirror the
    /// static gauge boundaries so the reset color lines up visually with the
    /// 5-hour gauge elsewhere in the app.
    private static func smartResetNSColor(
        utilization: Double,
        resetDate: Date,
        themeColors: ThemeColors,
        now: Date = Date()
    ) -> NSColor {
        let remainingMinutes = max(resetDate.timeIntervalSince(now), 0) / 60
        let risk = utilization * remainingMinutes / 100
        if risk > 100 { return themeColors.gaugeNSColor(for: 100, thresholds: .default) }
        if risk > 70 { return themeColors.gaugeNSColor(for: 75, thresholds: .default) }
        return themeColors.gaugeNSColor(for: 10, thresholds: .default)
    }

    // MARK: - Rendering

    private static func renderPinnedMetrics(_ data: RenderData) -> NSImage {
        let height: CGFloat = 22
        let str = NSMutableAttributedString()

        let sepAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        let ordered: [MetricID] = [
            .sessionReset, .fiveHour, .sessionPacing, .sevenDay, .weeklyPacing, .sonnet
        ].filter {
            guard data.pinnedMetrics.contains($0) else { return false }
            if !data.displaySonnet && $0 == .sonnet { return false }
            switch $0 {
            // Session-scoped pins stay visible as long as the API returned a
            // five_hour bucket. Between sessions Anthropic omits resets_at, so
            // we render a neutral placeholder rather than silently hiding a
            // pin the user explicitly asked for.
            case .sessionReset, .sessionPacing: return data.hasFiveHourBucket
            case .weeklyPacing: return data.hasWeeklyPacing
            default: return true
            }
        }
        for (i, metric) in ordered.enumerated() {
            if i > 0 {
                str.append(NSAttributedString(string: "  ", attributes: sepAttrs))
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
            case .fiveHour, .sevenDay, .sonnet:
                let value: Int
                switch metric {
                case .fiveHour: value = data.fiveHourPct
                case .sevenDay: value = data.sevenDayPct
                case .sonnet: value = data.sonnetPct
                default: value = 0
                }
                let periodLabelAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: periodColor(data),
                ]
                str.append(NSAttributedString(string: "\(metric.shortLabel) ", attributes: periodLabelAttrs))
                let pctAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: colorForPct(value, data: data),
                ]
                str.append(NSAttributedString(string: "\(value)%", attributes: pctAttrs))
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
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: resetValueColor(data),
        ]
        str.append(NSAttributedString(string: text, attributes: attrs))
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
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: dotColor,
        ]
        let deltaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: dotColor,
        ]
        let sign = delta >= 0 ? "+" : ""
        switch mode {
        case .dot:
            str.append(NSAttributedString(string: "\u{25CF}", attributes: dotAttrs))
        case .dotDelta:
            str.append(NSAttributedString(string: "\u{25CF}", attributes: dotAttrs))
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
        let neutralColor: NSColor = data.menuBarMonochrome
            ? .tertiaryLabelColor
            : .tertiaryLabelColor
        let dotAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: neutralColor,
        ]
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: neutralColor,
        ]
        switch mode {
        case .dot:
            str.append(NSAttributedString(string: "\u{25CF}", attributes: dotAttrs))
        case .dotDelta:
            str.append(NSAttributedString(string: "\u{25CF}", attributes: dotAttrs))
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

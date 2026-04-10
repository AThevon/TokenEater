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
        let sonnetPacingDelta: Int
        let sonnetPacingZone: PacingZone
        let hasSonnetPacing: Bool
        let sessionPacingDelta: Int
        let sessionPacingZone: PacingZone
        let hasSessionPacing: Bool
        let pacingDisplayMode: PacingDisplayMode
        let hasConfig: Bool
        let hasError: Bool
        let themeColors: ThemeColors
        let thresholds: UsageThresholds
        let menuBarMonochrome: Bool
        let fiveHourReset: String
        let showSessionReset: Bool
        let gaugeColorMode: GaugeColorMode
        let fiveHourResetDate: Date?
    }

    private static var cachedImage: NSImage?
    private static var cachedData: RenderData?

    static func render(_ data: RenderData) -> NSImage {
        if let cached = cachedImage, let prev = cachedData, prev == data {
            return cached
        }

        let image: NSImage
        if !data.hasConfig || data.hasError {
            image = renderLogoTemplate()
        } else {
            image = renderPinnedMetrics(data)
        }

        cachedImage = image
        cachedData = data
        return image
    }

    // MARK: - Color helpers

    private static func colorForPct(_ pct: Int, data: RenderData) -> NSColor {
        if data.menuBarMonochrome { return .labelColor }
        return data.themeColors.gaugeNSColor(for: Double(pct), thresholds: data.thresholds)
    }

    private static func colorForFiveHour(_ data: RenderData) -> NSColor {
        if data.menuBarMonochrome { return .labelColor }
        guard data.gaugeColorMode == .smart else {
            return data.themeColors.gaugeNSColor(for: Double(data.fiveHourPct), thresholds: data.thresholds)
        }
        return data.themeColors.smartGaugeNSColor(
            utilization: Double(data.fiveHourPct),
            resetDate: data.fiveHourResetDate
        )
    }

    private static func colorForZone(_ zone: PacingZone, data: RenderData) -> NSColor {
        if data.menuBarMonochrome { return .labelColor }
        return data.themeColors.pacingNSColor(for: zone)
    }

    // MARK: - Rendering

    private static func renderPinnedMetrics(_ data: RenderData) -> NSImage {
        let height: CGFloat = 22
        let str = NSMutableAttributedString()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let sepAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        let ordered: [MetricID] = [
            .fiveHour, .sessionPacing, .sevenDay, .weeklyPacing, .sonnet, .sonnetPacing
        ].filter {
            guard data.pinnedMetrics.contains($0) else { return false }
            if !data.displaySonnet && ($0 == .sonnet || $0 == .sonnetPacing) { return false }
            switch $0 {
            case .sessionPacing: return data.hasSessionPacing
            case .weeklyPacing: return data.hasWeeklyPacing
            case .sonnetPacing: return data.hasSonnetPacing
            default: return true
            }
        }
        for (i, metric) in ordered.enumerated() {
            if i > 0 {
                str.append(NSAttributedString(string: "  ", attributes: sepAttrs))
            }
            switch metric {
            case .sessionPacing:
                appendPacing(
                    to: str,
                    delta: data.sessionPacingDelta,
                    zone: data.sessionPacingZone,
                    data: data
                )
            case .weeklyPacing:
                appendPacing(
                    to: str,
                    delta: data.weeklyPacingDelta,
                    zone: data.weeklyPacingZone,
                    data: data
                )
            case .sonnetPacing:
                appendPacing(
                    to: str,
                    delta: data.sonnetPacingDelta,
                    zone: data.sonnetPacingZone,
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
                if metric == .fiveHour && data.showSessionReset && !data.fiveHourReset.isEmpty {
                    let resetLabelAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                        .foregroundColor: NSColor.tertiaryLabelColor,
                    ]
                    let resetValueAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                        .foregroundColor: NSColor.labelColor,
                    ]
                    str.append(NSAttributedString(string: "5h ", attributes: resetLabelAttrs))
                    str.append(NSAttributedString(string: data.fiveHourReset, attributes: resetValueAttrs))
                    str.append(NSAttributedString(string: "  ", attributes: labelAttrs))
                }
                str.append(NSAttributedString(string: "\(metric.shortLabel) ", attributes: labelAttrs))
                let color: NSColor
                if metric == .fiveHour {
                    color = colorForFiveHour(data)
                } else {
                    color = colorForPct(value, data: data)
                }
                let pctAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: color,
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

    private static func appendPacing(
        to str: NSMutableAttributedString,
        delta: Int,
        zone: PacingZone,
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
        switch data.pacingDisplayMode {
        case .dot:
            str.append(NSAttributedString(string: "\u{25CF}", attributes: dotAttrs))
        case .dotDelta:
            str.append(NSAttributedString(string: "\u{25CF}", attributes: dotAttrs))
            str.append(NSAttributedString(string: " \(sign)\(delta)%", attributes: deltaAttrs))
        case .delta:
            str.append(NSAttributedString(string: "\(sign)\(delta)%", attributes: deltaAttrs))
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

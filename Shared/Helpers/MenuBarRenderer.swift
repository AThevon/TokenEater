import AppKit

enum MenuBarRenderer {
    // FIX 1: Equatable RenderData with pure data (no closures)
    struct RenderData: Equatable {
        let pinnedMetrics: Set<MetricID>
        let fiveHourPct: Int
        let sevenDayPct: Int
        let sonnetPct: Int
        let pacingDelta: Int
        let pacingZone: PacingZone
        let pacingDisplayMode: PacingDisplayMode
        let hasConfig: Bool
        let hasError: Bool
        let themeColors: ThemeColors
        let thresholds: UsageThresholds
        let menuBarMonochrome: Bool
    }

    // FIX 1: Static cache — returns same NSImage when data unchanged
    private static var cachedImage: NSImage?
    private static var cachedData: RenderData?

    static func render(_ data: RenderData) -> NSImage {
        if let cached = cachedImage, let prev = cachedData, prev == data {
            return cached
        }

        let image: NSImage
        if !data.hasConfig || data.hasError {
            image = renderText("--", color: .tertiaryLabelColor)
        } else {
            image = renderPinnedMetrics(data)
        }

        cachedImage = image
        cachedData = data
        return image
    }

    // MARK: - Color helpers (replaces closures)

    private static func colorForPct(_ pct: Int, data: RenderData) -> NSColor {
        if data.menuBarMonochrome { return .labelColor }
        return data.themeColors.gaugeNSColor(for: Double(pct), thresholds: data.thresholds)
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

        let ordered: [MetricID] = [.fiveHour, .sevenDay, .sonnet, .pacing].filter { data.pinnedMetrics.contains($0) }
        for (i, metric) in ordered.enumerated() {
            if i > 0 {
                str.append(NSAttributedString(string: "  ", attributes: sepAttrs))
            }
            if metric == .pacing {
                let dotColor = colorForZone(data.pacingZone, data: data)
                let dotAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: dotColor,
                ]
                str.append(NSAttributedString(string: "\u{25CF}", attributes: dotAttrs))
                if data.pacingDisplayMode == .dotDelta {
                    let sign = data.pacingDelta >= 0 ? "+" : ""
                    let deltaAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
                        .foregroundColor: dotColor,
                    ]
                    str.append(NSAttributedString(string: " \(sign)\(data.pacingDelta)%", attributes: deltaAttrs))
                }
            } else {
                let value: Int
                switch metric {
                case .fiveHour: value = data.fiveHourPct
                case .sevenDay: value = data.sevenDayPct
                case .sonnet: value = data.sonnetPct
                case .pacing: value = 0
                }
                str.append(NSAttributedString(string: "\(metric.shortLabel) ", attributes: labelAttrs))
                let pctAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: colorForPct(value, data: data),
                ]
                str.append(NSAttributedString(string: "\(value)%", attributes: pctAttrs))
            }
        }

        // FIX 4: Modern NSImage API (replaces deprecated lockFocus/unlockFocus)
        let size = str.size()
        let imgSize = NSSize(width: ceil(size.width) + 2, height: height)
        let img = NSImage(size: imgSize, flipped: false) { _ in
            str.draw(at: NSPoint(x: 1, y: (height - size.height) / 2))
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func renderText(_ text: String, color: NSColor) -> NSImage {
        let height: CGFloat = 22
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: color,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let imgSize = NSSize(width: ceil(size.width) + 2, height: height)
        let img = NSImage(size: imgSize, flipped: false) { _ in
            str.draw(at: NSPoint(x: 1, y: (height - size.height) / 2))
            return true
        }
        img.isTemplate = false
        return img
    }
}

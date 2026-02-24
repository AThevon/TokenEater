import AppKit

enum MenuBarRenderer {
    struct RenderData {
        let pinnedMetrics: Set<MetricID>
        let fiveHourPct: Int
        let sevenDayPct: Int
        let sonnetPct: Int
        let pacingDelta: Int
        let pacingZone: PacingZone
        let pacingDisplayMode: PacingDisplayMode
        let hasConfig: Bool
        let hasError: Bool
        let colorForPct: (Int) -> NSColor
        let colorForZone: (PacingZone) -> NSColor
    }

    static func render(_ data: RenderData) -> NSImage {
        guard data.hasConfig, !data.hasError else {
            return renderText("--", color: .tertiaryLabelColor)
        }
        return renderPinnedMetrics(data)
    }

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
                let dotColor = data.colorForZone(data.pacingZone)
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
                    .foregroundColor: data.colorForPct(value),
                ]
                str.append(NSAttributedString(string: "\(value)%", attributes: pctAttrs))
            }
        }

        let size = str.size()
        let imgSize = NSSize(width: ceil(size.width) + 2, height: height)
        let img = NSImage(size: imgSize)
        img.lockFocus()
        str.draw(at: NSPoint(x: 1, y: (height - size.height) / 2))
        img.unlockFocus()
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
        let img = NSImage(size: NSSize(width: ceil(size.width) + 2, height: height))
        img.lockFocus()
        str.draw(at: NSPoint(x: 1, y: (height - size.height) / 2))
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

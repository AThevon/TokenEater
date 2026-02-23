import WidgetKit
import SwiftUI

struct ClaudeUsageWidget: Widget {
    let kind: String = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            UsageWidgetView(entry: entry)
        }
        .configurationDisplayName("TokenEater")
        .description(String(localized: "widget.description.usage"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PacingWidget: Widget {
    let kind: String = "PacingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PacingWidgetView(entry: entry)
        }
        .configurationDisplayName("TokenEater Pacing")
        .description(String(localized: "widget.description.pacing"))
        .supportedFamilies([.systemSmall])
    }
}

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeUsageWidget()
        PacingWidget()
    }
}

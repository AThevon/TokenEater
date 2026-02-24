import WidgetKit
import SwiftUI

struct TokenEaterWidget: Widget {
    let kind: String = "TokenEaterWidget"

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
struct TokenEaterWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenEaterWidget()
        PacingWidget()
    }
}

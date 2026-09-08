import WidgetKit
import SwiftUI

struct CodexUsageWidget: Widget {
    let kind = "CodexUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexProvider()) { entry in
            CodexUsageWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.gallery.codex"))
        .description(String(localized: "widget.description.codex"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

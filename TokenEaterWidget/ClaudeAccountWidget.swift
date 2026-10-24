import WidgetKit
import SwiftUI

/// Small + medium widget showing one tracked Claude account, chosen in Edit
/// Widget: the Session Ring in small, the Claude Overview in medium, under
/// the account's name and colour. The other Claude widgets keep following the
/// main account; this kind is the one that can be placed once per account.
struct ClaudeAccountWidget: Widget {
    let kind: String = "ClaudeAccountWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectClaudeAccountIntent.self,
            provider: ClaudeAccountProvider()
        ) { entry in
            ClaudeAccountWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.gallery.claude.account"))
        .description(String(localized: "widget.description.account"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

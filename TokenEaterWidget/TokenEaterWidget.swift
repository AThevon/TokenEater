import WidgetKit
import SwiftUI

struct TokenEaterWidget: Widget {
    let kind: String = "TokenEaterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticProvider()) { entry in
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
        StaticConfiguration(kind: kind, provider: StaticProvider()) { entry in
            PacingGlanceWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.title.pacingGlance"))
        .description(String(localized: "widget.description.pacing"))
        .supportedFamilies([.systemSmall])
    }
}

/// Small widget : single big ring gauge for the 5h session, Smart Color v2 driven.
struct SessionRingWidget: Widget {
    let kind: String = "SessionRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticProvider()) { entry in
            SessionRingWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.title.sessionRing"))
        .description(String(localized: "widget.description.sessionRing"))
        .supportedFamilies([.systemSmall])
    }
}

/// Medium widget : signature pacing graph (equilibrium diagonal + actual trajectory).
struct PacingGraphWidget: Widget {
    let kind: String = "PacingGraphWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticProvider()) { entry in
            PacingGraphWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.title.pacingGraph"))
        .description(String(localized: "widget.description.pacingGraph"))
        .supportedFamilies([.systemMedium])
    }
}

/// Large widget : last 7 days tokens-over-time bar chart with delta vs yesterday.
struct HistorySparklineWidget: Widget {
    let kind: String = "HistorySparklineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StaticProvider()) { entry in
            HistorySparklineWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "widget.title.historySparkline"))
        .description(String(localized: "widget.description.historySparkline"))
        .supportedFamilies([.systemLarge])
    }
}

@main
struct TokenEaterWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenEaterWidget()
        PacingWidget()
        SessionRingWidget()
        PacingGraphWidget()
        HistorySparklineWidget()
    }
}

import AppIntents
import WidgetKit

struct RefreshWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Refresh TokenEater Widget"
    static var description: IntentDescription = "Forces a refresh of the widget timeline"

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

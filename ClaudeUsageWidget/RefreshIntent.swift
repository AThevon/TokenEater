import AppIntents
import WidgetKit

struct RefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.refresh.button"
    static var description: IntentDescription = "widget.refresh.button"

    func perform() async throws -> some IntentResult {
        _ = try? await ClaudeAPIClient.shared.fetchUsage()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

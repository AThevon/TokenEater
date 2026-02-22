import WidgetKit
import Foundation

struct Provider: AppIntentTimelineProvider {
    private let apiClient = ClaudeAPIClient.shared

    func placeholder(in context: Context) -> UsageEntry {
        .placeholder
    }

    func snapshot(for configuration: ProxyIntent, in context: Context) async -> UsageEntry {
        if context.isPreview {
            return .placeholder
        }
        applyProxy(configuration)
        return await fetchEntry()
    }

    func timeline(for configuration: ProxyIntent, in context: Context) async -> Timeline<UsageEntry> {
        applyProxy(configuration)
        let entry = await fetchEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func applyProxy(_ configuration: ProxyIntent) {
        apiClient.proxyConfig = ProxyConfig(
            enabled: configuration.proxyEnabled,
            host: configuration.proxyHost,
            port: configuration.proxyPort
        )
    }

    private func fetchEntry() async -> UsageEntry {
        guard apiClient.isConfigured else {
            return .unconfigured
        }

        do {
            let usage = try await apiClient.fetchUsage()
            return UsageEntry(date: Date(), usage: usage)
        } catch {
            if let cached = apiClient.loadCachedUsage() {
                return UsageEntry(
                    date: Date(),
                    usage: cached.usage,
                    error: nil,
                    isStale: true
                )
            }
            return UsageEntry(date: Date(), usage: nil, error: error.localizedDescription)
        }
    }
}

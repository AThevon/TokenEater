import AppIntents
import WidgetKit

struct ProxyIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "TokenEater Configuration"
    static var description: IntentDescription = "Configure proxy settings for the widget"

    @Parameter(title: "Enable SOCKS5 Proxy", default: false)
    var proxyEnabled: Bool

    @Parameter(title: "Proxy Host", default: "127.0.0.1")
    var proxyHost: String

    @Parameter(title: "Proxy Port", default: 1080)
    var proxyPort: Int
}

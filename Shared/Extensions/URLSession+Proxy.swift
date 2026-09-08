import Foundation

extension URLSession {
    /// Session honouring the user's SOCKS proxy setting, shared by every API
    /// client so the Claude and Codex calls always agree on the transport.
    /// Syntactically invalid proxy targets are rejected before they reach
    /// `connectionProxyDictionary`, falling back to the default session.
    static func tokenEater(proxyConfig: ProxyConfig?) -> URLSession {
        guard let proxy = proxyConfig, proxy.isValidForUse else { return .shared }
        let configuration = URLSessionConfiguration.default
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable as String: true,
            kCFNetworkProxiesSOCKSProxy as String: proxy.host,
            kCFNetworkProxiesSOCKSPort as String: proxy.port,
        ]
        return URLSession(configuration: configuration)
    }
}

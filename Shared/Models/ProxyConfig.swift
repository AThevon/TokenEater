import Foundation

struct ProxyConfig {
    var enabled: Bool
    var host: String
    var port: Int

    init(enabled: Bool = false, host: String = "127.0.0.1", port: Int = 1080) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }

    /// Returns true when the host + port look like a syntactically valid
    /// SOCKS proxy target. Refuses empty / control-char / slash-injected
    /// hosts and out-of-range ports before they reach
    /// `URLSessionConfiguration.connectionProxyDictionary`.
    var isValidForUse: Bool {
        guard enabled else { return false }
        guard (1...65535).contains(port) else { return false }
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 253,
              !trimmed.contains(" ") else { return false }
        let invalid = CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: "/\\?#@\""))
        return trimmed.unicodeScalars.allSatisfy { !invalid.contains($0) }
    }
}

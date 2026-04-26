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
    /// SOCKS proxy target. The main app is desandboxed since v5.0, so a
    /// tampered UserDefaults plist could in theory point the proxy at an
    /// arbitrary attacker-controlled host and route the OAuth bearer
    /// through it. This is a cheap syntactic gate before
    /// `URLSessionConfiguration.connectionProxyDictionary` accepts the
    /// host. The Anthropic API enforces TLS regardless, so even a
    /// successful proxy hijack still hits a server-validated cert chain,
    /// but it's correct hygiene to refuse obviously malformed input.
    var isValidForUse: Bool {
        guard enabled else { return false }
        guard (1...65535).contains(port) else { return false }
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 253,
              !trimmed.contains(" ") else { return false }
        // Hostnames + IPv4 + IPv6 (bracketed). Accept anything that looks
        // like a name or numeric address; reject control chars and obvious
        // garbage.
        let invalid = CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: "/\\?#@\""))
        return trimmed.unicodeScalars.allSatisfy { !invalid.contains($0) }
    }
}

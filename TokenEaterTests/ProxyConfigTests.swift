import Testing
import Foundation

/// Validates the syntactic gate `APIClient` uses before handing a host /
/// port pair to `URLSessionConfiguration.connectionProxyDictionary`. The
/// main app is desandboxed since v5.0, so a tampered UserDefaults plist
/// could in theory point the proxy at an arbitrary host; rejecting
/// obviously malformed input is cheap hygiene.
@Suite("ProxyConfig.isValidForUse")
struct ProxyConfigTests {

    @Test("Disabled config is invalid even with a clean host/port")
    func disabledRejected() {
        let cfg = ProxyConfig(enabled: false, host: "127.0.0.1", port: 1080)
        #expect(cfg.isValidForUse == false)
    }

    @Test("Loopback IPv4 + standard SOCKS port is valid")
    func loopbackAccepted() {
        let cfg = ProxyConfig(enabled: true, host: "127.0.0.1", port: 1080)
        #expect(cfg.isValidForUse == true)
    }

    @Test("Hostname with dots and dashes is valid")
    func hostnameAccepted() {
        let cfg = ProxyConfig(enabled: true, host: "proxy.internal.example.com", port: 443)
        #expect(cfg.isValidForUse == true)
    }

    @Test("Bracketed IPv6 is valid")
    func ipv6Accepted() {
        let cfg = ProxyConfig(enabled: true, host: "[::1]", port: 1080)
        #expect(cfg.isValidForUse == true)
    }

    @Test("Empty host is rejected")
    func emptyHostRejected() {
        let cfg = ProxyConfig(enabled: true, host: "", port: 1080)
        #expect(cfg.isValidForUse == false)
    }

    @Test("Host with whitespace only is rejected")
    func whitespaceHostRejected() {
        let cfg = ProxyConfig(enabled: true, host: "   ", port: 1080)
        #expect(cfg.isValidForUse == false)
    }

    @Test("Host with a space inside is rejected")
    func hostWithSpaceRejected() {
        let cfg = ProxyConfig(enabled: true, host: "evil host.com", port: 1080)
        #expect(cfg.isValidForUse == false)
    }

    @Test("Host with a slash (URL injection) is rejected")
    func slashHostRejected() {
        let cfg = ProxyConfig(enabled: true, host: "evil.com/exfiltrate", port: 1080)
        #expect(cfg.isValidForUse == false)
    }

    @Test("Host with control characters is rejected")
    func controlCharsRejected() {
        let cfg = ProxyConfig(enabled: true, host: "evil\u{0000}.com", port: 1080)
        #expect(cfg.isValidForUse == false)
    }

    @Test("Port out of range is rejected")
    func portOutOfRangeRejected() {
        let zero = ProxyConfig(enabled: true, host: "127.0.0.1", port: 0)
        let too_high = ProxyConfig(enabled: true, host: "127.0.0.1", port: 65536)
        let negative = ProxyConfig(enabled: true, host: "127.0.0.1", port: -1)
        #expect(zero.isValidForUse == false)
        #expect(too_high.isValidForUse == false)
        #expect(negative.isValidForUse == false)
    }

    @Test("Port boundaries are accepted")
    func portBoundariesAccepted() {
        let low = ProxyConfig(enabled: true, host: "127.0.0.1", port: 1)
        let high = ProxyConfig(enabled: true, host: "127.0.0.1", port: 65535)
        #expect(low.isValidForUse == true)
        #expect(high.isValidForUse == true)
    }

    @Test("Host longer than 253 chars is rejected")
    func hostnameTooLongRejected() {
        let host = String(repeating: "a", count: 254)
        let cfg = ProxyConfig(enabled: true, host: host, port: 1080)
        #expect(cfg.isValidForUse == false)
    }
}

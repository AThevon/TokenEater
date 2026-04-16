import Testing
import Foundation

@Suite("AppcastXMLParser")
struct AppcastXMLParserTests {
    private func parse(_ xml: String) -> AppcastXMLParser {
        let parser = AppcastXMLParser()
        parser.parse(data: Data(xml.utf8))
        return parser
    }

    private let header = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>
                <title>TokenEater</title>
        """

    private let footer = """
            </channel>
        </rss>
        """

    @Test("parses version, URL, signature, and length from an enclosure")
    func parsesSignedEnclosure() {
        let xml = """
        \(header)
            <item>
                <title>5.0.0</title>
                <sparkle:version>5.0.0</sparkle:version>
                <enclosure url="https://example.com/TokenEater.dmg" sparkle:edSignature="AAAA==" length="1234" type="application/octet-stream" />
            </item>
        \(footer)
        """
        let parser = parse(xml)

        let latest = parser.latestItem
        #expect(latest?.version == "5.0.0")
        #expect(latest?.downloadURL.absoluteString == "https://example.com/TokenEater.dmg")
        #expect(latest?.edSignature == "AAAA==")
        #expect(latest?.expectedLength == 1234)
    }

    @Test("preserves empty signature string (does not coerce to nil)")
    func parsesEmptySignature() {
        let xml = """
        \(header)
            <item>
                <sparkle:version>4.7.5</sparkle:version>
                <enclosure url="https://example.com/TokenEater.dmg" sparkle:edSignature="" length="2048" type="application/octet-stream" />
            </item>
        \(footer)
        """
        let parser = parse(xml)
        #expect(parser.latestItem?.edSignature == "")
    }

    @Test("returns nil signature when attribute is absent")
    func parsesMissingSignatureAsNil() {
        let xml = """
        \(header)
            <item>
                <sparkle:version>4.6.0</sparkle:version>
                <enclosure url="https://example.com/TokenEater.dmg" length="512" type="application/octet-stream" />
            </item>
        \(footer)
        """
        let parser = parse(xml)
        #expect(parser.latestItem?.edSignature == nil)
    }

    @Test("returns nil length when attribute is absent")
    func parsesMissingLengthAsNil() {
        let xml = """
        \(header)
            <item>
                <sparkle:version>4.6.0</sparkle:version>
                <enclosure url="https://example.com/TokenEater.dmg" sparkle:edSignature="AAAA==" type="application/octet-stream" />
            </item>
        \(footer)
        """
        let parser = parse(xml)
        #expect(parser.latestItem?.expectedLength == nil)
    }

    @Test("returns nil length when length is not a valid integer")
    func parsesInvalidLengthAsNil() {
        let xml = """
        \(header)
            <item>
                <sparkle:version>4.6.0</sparkle:version>
                <enclosure url="https://example.com/TokenEater.dmg" sparkle:edSignature="AAAA==" length="nope" type="application/octet-stream" />
            </item>
        \(footer)
        """
        let parser = parse(xml)
        #expect(parser.latestItem?.expectedLength == nil)
    }

    @Test("resets state between items (signature does not leak forward)")
    func doesNotLeakSignatureBetweenItems() {
        let xml = """
        \(header)
            <item>
                <sparkle:version>5.0.0</sparkle:version>
                <enclosure url="https://example.com/a.dmg" sparkle:edSignature="SIGA==" length="100" type="application/octet-stream" />
            </item>
            <item>
                <sparkle:version>5.1.0</sparkle:version>
                <enclosure url="https://example.com/b.dmg" length="200" type="application/octet-stream" />
            </item>
        \(footer)
        """
        let parser = parse(xml)

        #expect(parser.items.count == 2)
        let itemA = parser.items.first(where: { $0.version == "5.0.0" })
        let itemB = parser.items.first(where: { $0.version == "5.1.0" })
        #expect(itemA?.edSignature == "SIGA==")
        #expect(itemB?.edSignature == nil)
        #expect(parser.latestItem?.version == "5.1.0")
    }

    @Test("selects the highest semver item as latest")
    func selectsHighestVersion() {
        let xml = """
        \(header)
            <item><sparkle:version>4.6.0</sparkle:version><enclosure url="https://example.com/old.dmg" /></item>
            <item><sparkle:version>5.0.0</sparkle:version><enclosure url="https://example.com/new.dmg" sparkle:edSignature="NEW==" length="999" /></item>
            <item><sparkle:version>4.9.3</sparkle:version><enclosure url="https://example.com/mid.dmg" /></item>
        \(footer)
        """
        let parser = parse(xml)
        #expect(parser.latestItem?.version == "5.0.0")
        #expect(parser.latestItem?.edSignature == "NEW==")
    }
}

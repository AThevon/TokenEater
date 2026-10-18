import Testing
import Foundation

/// Transcripts are read one block at a time instead of whole, so the line
/// splitter has to give exactly the lines a whole-file read would.
@Suite("SessionHistoryService line streaming")
struct SessionHistoryStreamingTests {

    private func lines(of content: Data, containing marker: String = "input_tokens") throws -> [String] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("streaming-\(UUID().uuidString).jsonl")
        try content.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var found: [String] = []
        try SessionHistoryService.forEachLine(in: handle, containing: Data(marker.utf8)) {
            found.append(String(decoding: $0, as: UTF8.self))
        }
        return found
    }

    @Test("keeps only the lines holding the marker, the last one without a newline too")
    func filtersAndKeepsTrailingLine() throws {
        let content = """
        {"type":"user","text":"hi"}
        {"message":{"usage":{"input_tokens":1}}}
        {"type":"system"}
        {"message":{"usage":{"input_tokens":2}}}
        """
        #expect(try lines(of: Data(content.utf8)) == [
            #"{"message":{"usage":{"input_tokens":1}}}"#,
            #"{"message":{"usage":{"input_tokens":2}}}"#,
        ])
    }

    @Test("a line longer than one read block arrives whole")
    func lineAcrossBlocks() throws {
        let filler = String(repeating: "x", count: 1_500_000)
        let long = #"{"pad":""# + filler + #"","input_tokens":3}"#
        let content = "{\"a\":1}\n" + long + "\n{\"input_tokens\":4}\n"
        let found = try lines(of: Data(content.utf8))
        #expect(found.count == 2)
        #expect(found.first == long)
        #expect(found.last == #"{"input_tokens":4}"#)
    }

    @Test("a Unicode line separator inside a record does not split it")
    func unicodeSeparatorStaysInside() throws {
        let record = "{\"text\":\"a\u{2028}b\",\"input_tokens\":5}"
        let found = try lines(of: Data((record + "\n").utf8))
        #expect(found == [record])
        let parsed = try JSONSerialization.jsonObject(with: Data(found[0].utf8)) as? [String: Any]
        #expect(parsed?["input_tokens"] as? Int == 5)
    }

    @Test("an empty file gives nothing")
    func emptyFile() throws {
        #expect(try lines(of: Data()).isEmpty)
    }
}

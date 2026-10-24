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

    @Test("a line spanning several blocks, and a newline right on a block edge, split as a whole read would")
    func linesAcrossManyBlocks() throws {
        let block = 1 << 20
        // A record that ends exactly where the first block does.
        let edge = #"{"input_tokens":6,"pad":""# + String(repeating: "y", count: block - 28) + #""}"#
        #expect(edge.utf8.count == block - 1)
        let huge = #"{"pad":""# + String(repeating: "z", count: 3 * block + 123) + #"","input_tokens":7}"#
        let content = edge + "\n" + huge + "\n" + "{\"input_tokens\":8}"
        let found = try lines(of: Data(content.utf8))
        #expect(found.count == 3)
        #expect(found[0] == edge)
        #expect(found[1] == huge)
        #expect(found[2] == #"{"input_tokens":8}"#)
    }

    @Test("a transcript that cannot be read is skipped, a cancelled scan still stops")
    func unreadableIsSkippedButCancellationIsNot() throws {
        struct ReadFailure: Error {}
        let skipped: Int? = try SessionHistoryService.skippingUnreadable { () throws -> Int in throw ReadFailure() }
        #expect(skipped == nil)
        let read: Int? = try SessionHistoryService.skippingUnreadable { 3 }
        #expect(read == 3)
        #expect(throws: CancellationError.self) {
            _ = try SessionHistoryService.skippingUnreadable { () throws -> Int in throw CancellationError() }
        }
    }

    @Test("an empty file gives nothing")
    func emptyFile() throws {
        #expect(try lines(of: Data()).isEmpty)
    }
}

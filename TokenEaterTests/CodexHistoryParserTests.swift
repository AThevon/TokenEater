import Foundation
import Testing

@Suite("Codex token history")
struct CodexHistoryParserTests {
    // MARK: - Tests

    @Test("Response records, mirrored events, and duplicate responses count once")
    func modernRecords() throws {
        let record = event("token_usage_record", ["thread_id": "s", "response_id": "r1", "usage": usage(1000, 600, 100, written: 100)])
        let entry = try parse([
            meta(), context("gpt-6-astra"), record,
            tokenCount(usage(1000, 600, 100, written: 100)), record,
            event("event_msg", ["type": "token_count", "info": NSNull()])
        ])
        let bucket = try #require(entry.buckets.first)
        #expect(bucket.totalActive == 500)
        #expect(bucket.inputTokens == 300)
        #expect(bucket.outputTokens == 100)
        #expect(bucket.cacheReadTokens == 600)
        #expect(bucket.cacheCreateTokens == 100)
        #expect(bucket.totalIncludingCache == 1100)
        #expect(bucket.cachedTokens == 600)
        #expect(bucket.totalActive + bucket.cachedTokens == bucket.totalIncludingCache)
        #expect(bucket.tokensByModel[.codex(model: "gpt-6-astra")] == 500)
        #expect(bucket.sessionsCount == 1)
    }

    @Test("Cumulative legacy counters suppress repeated rate-limit updates")
    func legacyCounters() throws {
        let first = usage(1000, 600, 100)
        let second = usage(1400, 800, 150)
        let entry = try parse([
            meta(), context("gpt-5.6-sol"), tokenCount(first), tokenCount(first),
            tokenCount(second), tokenCount(second)
        ])
        #expect(entry.buckets.first?.totalActive == 750)
        #expect(entry.buckets.first?.cacheReadTokens == 800)
    }

    @Test("An upgraded log retains legacy usage before its first response record")
    func mixedFormats() throws {
        let entry = try parse([
            meta(), context("gpt-5.6-sol"), tokenCount(usage(1000, 600, 100), second: 1),
            event("token_usage_record", ["thread_id": "s", "response_id": "r1", "usage": usage(200, 100, 50)], second: 2),
            tokenCount(usage(1200, 700, 150), second: 2)
        ])
        #expect(entry.buckets.first?.totalActive == 650)
    }

    @Test("Forked logs do not count parent response records")
    func foreignResponses() throws {
        let entry = try parse([
            meta(), context("gpt-6-astra"),
            event("token_usage_record", ["thread_id": "parent", "response_id": "parent-r", "usage": usage(9999, 0, 100)]),
            event("token_usage_record", ["thread_id": "s", "response_id": "child-r", "usage": usage(100, 0, 20)])
        ])
        #expect(entry.buckets.first?.totalActive == 120)
    }

    @Test("Legacy replay establishes the baseline without billing inherited history")
    func legacyReplay() throws {
        let entry = try parse([
            meta(second: 2), context("gpt-5.6-sol"),
            tokenCount(usage(1000, 600, 100), second: 1),
            tokenCount(usage(1300, 700, 150), second: 3)
        ])
        #expect(entry.buckets.first?.totalActive == 250)
    }

    @Test("Counter resets use the last response; reasoning is already inside output")
    func resetCounters() throws {
        let entry = try parse([
            meta(), context("gpt-6-astra"), tokenCount(usage(1000, 600, 100), second: 1),
            tokenCount(usage(200, 100, 50), second: 2, last: usage(200, 100, 50))
        ])
        #expect(entry.buckets.first?.totalActive == 650)
    }

    @Test("Model and project changes remain attributable per turn")
    func modelChanges() throws {
        let entry = try parse([
            meta(), context("gpt-6-astra", turn: "a", cwd: "/repo-a"),
            event("token_usage_record", ["thread_id": "s", "turn_id": "a", "response_id": "r1", "usage": usage(100, 0, 20)]),
            context("future-model", turn: "b", cwd: "/repo-b"),
            event("token_usage_record", ["thread_id": "s", "turn_id": "b", "response_id": "r2", "usage": usage(200, 100, 30)])
        ])
        let bucket = try #require(entry.buckets.first)
        #expect(bucket.tokensByModel[.codex(model: "gpt-6-astra")] == 120)
        #expect(bucket.tokensByModel[.codex(model: "future-model")] == 130)
        #expect(bucket.tokensByProject == ["/repo-a": 120, "/repo-b": 130])
    }

    @Test("Malformed and partially written lines do not erase valid responses")
    func malformedLines() throws {
        let entry = try parse([
            meta(), "{broken", event("response_item", ["type": "message", "text": "input_tokens"]),
            event("token_usage_record", ["thread_id": "s", "response_id": "invalid", "usage": usage(10, 20, 1)]),
            event("token_usage_record", ["thread_id": "s", "response_id": "valid", "usage": usage(10, 0, 1)]),
            "{\"type\":\"token_usage_record\""
        ])
        #expect(entry.buckets.first?.totalActive == 11)
        #expect(entry.buckets.first?.tokensByModel[.codex(model: "")] == 11)
    }

    @Test("Dynamic model identifiers and existing enum cache strings round trip")
    func modelCompatibility() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(ModelKind.self, from: Data("\"opus5\"".utf8)) == .opus5)
        let model = ModelKind.codex(model: "future-model")
        #expect(try decoder.decode(ModelKind.self, from: JSONEncoder().encode(model)) == model)
        #expect(model.family.displayName == "future-model")
        #expect(ModelKind.codex(model: "gpt-6-astra").displayName == "GPT-6-astra")
        #expect(ModelKind.codex(model: "").displayName == "Codex")
        let bucket = try #require(parse([
            meta(), context("future-model"), tokenCount(usage(10, 0, 1))
        ]).buckets.first)
        #expect(try decoder.decode(HistoryBucket.self, from: JSONEncoder().encode(bucket)).tokensByModel == bucket.tokensByModel)
    }

    @Test("Guardian sessions are excluded even without a model label")
    func guardianSessions() throws {
        for metadata: [String: Any] in [
            ["id": "s", "thread_source": "guardian_review"],
            ["id": "s", "source": ["subagent": ["other": "guardian"]]]
        ] {
            let entry = try parse([
                event("session_meta", metadata),
                event("token_usage_record", ["thread_id": "s", "response_id": "r", "usage": usage(100, 0, 20)])
            ])
            #expect(entry.buckets.isEmpty)
        }
    }

    @Test("Auto-review events are omitted from modern and legacy mixed sessions")
    func autoReviewModel() throws {
        for modern in [false, true] {
            let entry = try parse([
                event("session_meta", ["id": "s", "source": "cli"]),
                context("codex-auto-review"),
                modern
                    ? event("token_usage_record", ["thread_id": "s", "response_id": "r1", "usage": usage(1000, 0, 100)], second: 1)
                    : tokenCount(usage(1000, 0, 100), second: 1),
                context("gpt-6-astra"),
                modern
                    ? event("token_usage_record", ["thread_id": "s", "response_id": "r2", "usage": usage(200, 0, 20)], second: 2)
                    : tokenCount(usage(1200, 0, 120), second: 2)
            ])
            #expect(entry.buckets.first?.totalActive == 220)
            #expect(entry.buckets.first?.sessionsCount == 1)
            #expect(entry.buckets.first?.tokensByModel.count == 1)
        }
    }

    // MARK: - Helpers

    private func parse(_ lines: [String]) throws -> HistoryFileCacheEntry {
        try CodexHistoryParser.parse(lines.joined(separator: "\n"), path: "/fixture.jsonl", mtime: Date())
    }

    private func usage(_ input: Int, _ cached: Int, _ output: Int, written: Int = 0) -> [String: Int] {
        ["input_tokens": input, "cached_input_tokens": cached, "cache_write_input_tokens": written,
         "output_tokens": output, "reasoning_output_tokens": output / 2, "total_tokens": input + output]
    }

    private func meta(second: Int = 0) -> String {
        event("session_meta", ["id": "s", "cwd": "/repo"], second: second)
    }

    private func context(_ model: String, turn: String = "t", cwd: String = "/repo") -> String {
        event("turn_context", ["model": model, "turn_id": turn, "cwd": cwd])
    }

    private func tokenCount(_ total: [String: Int], second: Int = 1, last: [String: Int]? = nil) -> String {
        var info = ["total_token_usage": total]
        if let last { info["last_token_usage"] = last }
        return event("event_msg", ["type": "token_count", "info": info], second: second)
    }

    private func event(_ type: String, _ payload: [String: Any], second: Int = 1) -> String {
        let value: [String: Any] = ["type": type, "payload": payload,
                                   "timestamp": String(format: "2026-09-08T12:00:%02d.000Z", second)]
        return String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
    }
}

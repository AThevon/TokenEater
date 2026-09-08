import Foundation
import Testing

@Suite("Combined Claude and Codex history")
struct CombinedHistoryTests {
    // MARK: - Tests

    @Test("Both providers merge by date, model, project and previous-period total")
    func aggregation() async throws {
        let day = Calendar.current.startOfDay(for: Date())
        let model = ModelKind.codex(model: "gpt-6-astra")
        let claude = Stub(buckets: [bucket(day, .opus5, 100)], previous: 20)
        let codex = Stub(buckets: [bucket(day, model, 200)], previous: 30)
        let service = CombinedSessionHistoryService(claude: claude, codex: codex)
        let combined = try await service.loadHistory(range: .sevenDays)
        #expect(combined.count == 1)
        #expect(combined.first?.totalActive == 300)
        #expect(combined.first?.tokensByProject["/repo"] == 300)
        #expect(combined.first?.sessionsCount == 2)
        #expect(try await service.loadPreviousPeriodActiveTokens(range: .sevenDays) == 50)
        #expect(HistoryStore.bucketsForChart(combined, filter: .family(model.family)).first?.totalActive == 200)
    }

    @Test("Missing Claude history still shows Codex")
    func codexOnly() async throws {
        let service = CombinedSessionHistoryService(
            claude: Stub(), codex: Stub(buckets: [bucket(Date(), .codex(model: "future"), 200)])
        )
        #expect(try await service.loadHistory(range: .sevenDays).first?.totalActive == 200)
    }

    @Test("Widget receives combined calendar-day totals without Claude authentication")
    @MainActor func widgetSnapshot() async throws {
        let day = Calendar.current.startOfDay(for: Date())
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: day))
        let service = CombinedSessionHistoryService(
            claude: Stub(buckets: [bucket(day, .opus5, 100)]),
            codex: Stub(buckets: [bucket(day, .codex(model: "future"), 200), bucket(yesterday, .codex(model: "future"), 50)])
        )
        let shared = MockSharedFileService()
        var reloads = 0
        let store = HistoryWidgetStore(service: service, sharedFile: shared, reloadWidget: { reloads += 1 })
        await store.refresh()
        #expect(shared.lastWeekDailyTotals == [0, 0, 0, 0, 0, 50, 300])
        #expect(reloads == 1)
        await store.refresh()
        #expect(reloads == 1)
        #expect(shared.isConfigured == false)
    }

    @Test("Failed refresh preserves the widget's last successful totals")
    @MainActor func failedWidgetRefresh() async {
        let shared = MockSharedFileService()
        shared._lastWeekDailyTotals = [1, 2, 3, 4, 5, 6, 7]
        let store = HistoryWidgetStore(service: Stub(fails: true), sharedFile: shared, reloadWidget: {})
        await store.refresh()
        #expect(shared.lastWeekDailyTotals == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test("Discovery includes archives, deduplicates sessions, and refreshes changed files")
    func discoveryAndCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions/2026/09/08")
        let archives = root.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archives, withIntermediateDirectories: true)
        let live = sessions.appendingPathComponent("rollout.jsonl")
        let archive = archives.appendingPathComponent("rollout.jsonl")
        let timestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        let lines = """
        {"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"s","cwd":"/repo"}}
        {"timestamp":"\(timestamp)","type":"turn_context","payload":{"model":"gpt-6-astra"}}
        {"timestamp":"\(timestamp)","type":"token_usage_record","payload":{"thread_id":"s","response_id":"r1","usage":{"input_tokens":100,"output_tokens":20}}}
        """
        try lines.write(to: live, atomically: true, encoding: .utf8)
        try lines.write(to: archive, atomically: true, encoding: .utf8)
        let service = SessionHistoryService(source: .codex, rootURL: root, cacheURL: root.appendingPathComponent("cache.json"))
        #expect(try await service.loadHistory(range: .sevenDays).reduce(0) { $0 + $1.totalActive } == 120)
        #expect(try await service.loadHistory(range: .sevenDays).reduce(0) { $0 + $1.totalActive } == 120)
        try FileManager.default.removeItem(at: archive)
        let extra = "\n" + """
        {"timestamp":"\(timestamp)","type":"token_usage_record","payload":{"thread_id":"s","response_id":"r2","usage":{"input_tokens":50,"output_tokens":10}}}
        """
        try (lines + extra).write(to: live, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(1)], ofItemAtPath: live.path)
        #expect(try await service.loadHistory(range: .sevenDays).reduce(0) { $0 + $1.totalActive } == 180)
    }

    @Test("Claude cache writes contribute to active tokens and are not cache hits")
    func claudeCacheWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        let line = """
        {"timestamp":"\(timestamp)","type":"assistant","sessionId":"s","cwd":"/repo","message":{"model":"claude-opus-5","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":200,"cache_read_input_tokens":650}}}
        """
        try line.write(to: root.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        let service = SessionHistoryService(rootURL: root, cacheURL: root.appendingPathComponent("cache.json"))
        let result = try await service.loadHistory(range: .sevenDays)
        let bucket = try #require(result.first)
        #expect(bucket.totalActive == 350)
        #expect(bucket.tokensByProject["/repo"] == 350)
        #expect(bucket.cachedTokens == 650)
        #expect(bucket.totalIncludingCache == 1000)
        #expect(bucket.totalActive + bucket.cachedTokens == bucket.totalIncludingCache)
        #expect(bucket.cacheHitRate == 0.65)
    }

    // MARK: - Helpers

    private func bucket(_ date: Date, _ model: ModelKind, _ tokens: Int) -> HistoryBucket {
        var bucket = HistoryBucket.merging(.empty, .empty, date: date)
        bucket.tokensByModel = [model: tokens]
        bucket.tokensByProject = ["/repo": tokens]
        bucket.inputTokens = tokens
        bucket.sessionsCount = 1
        return bucket
    }

    private struct Stub: SessionHistoryServiceProtocol {
        var buckets: [HistoryBucket] = []
        var previous: Int = 0
        var fails = false

        func loadHistory(range: HistoryRange) async throws -> [HistoryBucket] {
            if fails { throw CocoaError(.fileReadUnknown) }
            return buckets
        }

        func loadPreviousPeriodActiveTokens(range: HistoryRange) async throws -> Int { previous }
    }
}

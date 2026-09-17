import Testing
import Foundation

/// The history cache is what keeps a cold scan from re-parsing every JSONL
/// file on the machine. These tests pin the two properties that make it
/// actually work: a narrow scan must not throw away what a wide scan learned,
/// and the cache must not grow without bound.
@Suite("Session history cache retention")
struct SessionHistoryCacheTests {

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("history-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    private func writeSession(in root: URL, name: String, daysAgo: Int) throws -> URL {
        let url = root.appendingPathComponent("\(name).jsonl")
        try SessionJSONLFixture.fullSession.write(to: url, atomically: true, encoding: .utf8)
        let mtime = Date().addingTimeInterval(-Double(daysAgo) * 86_400)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        return url
    }

    /// File names, not full paths: the enumerator hands back `/private/var/...`
    /// while the literal URL says `/var/...`, and these tests are about which
    /// files the cache remembers, not about symlink trivia.
    private func cachedNames(_ cacheURL: URL) throws -> Set<String> {
        let data = try Data(contentsOf: cacheURL)
        let cache = try JSONDecoder().decode(HistoryCache.self, from: data)
        return Set(cache.entries.keys.map { ($0 as NSString).lastPathComponent })
    }

    @Test("A 7-day scan does not evict what a 30-day scan cached")
    func narrowScanKeepsWideEntries() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("history-cache.json")

        try writeSession(in: root, name: "recent", daysAgo: 1)
        try writeSession(in: root, name: "old", daysAgo: 20)

        let service = SessionHistoryService(rootURL: root, cacheURL: cacheURL)
        _ = try await service.loadHistory(range: .thirtyDays)
        #expect(try cachedNames(cacheURL) == ["recent.jsonl", "old.jsonl"])

        // The 7-day window cannot even see `old`, because the mtime filter
        // drops it before parsing. That must not be read as "this file no
        // longer matters": the next 30-day scan would re-parse it from
        // scratch, and on a real machine that is the whole cold-scan cost
        // paid again on every range switch.
        _ = try await service.loadHistory(range: .sevenDays)
        #expect(try cachedNames(cacheURL) == ["recent.jsonl", "old.jsonl"])
    }

    @Test("An entry whose file is gone is dropped, so the cache cannot grow forever")
    func deletedFilesArePruned() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("history-cache.json")

        try writeSession(in: root, name: "kept", daysAgo: 1)
        let removed = try writeSession(in: root, name: "removed", daysAgo: 2)

        let service = SessionHistoryService(rootURL: root, cacheURL: cacheURL)
        _ = try await service.loadHistory(range: .thirtyDays)
        #expect(try cachedNames(cacheURL) == ["kept.jsonl", "removed.jsonl"])

        try FileManager.default.removeItem(at: removed)
        _ = try await service.loadHistory(range: .thirtyDays)
        #expect(try cachedNames(cacheURL) == ["kept.jsonl"])
    }

    @Test("A second scan of unchanged files reuses the cache rather than reparsing")
    func unchangedFilesAreReused() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("history-cache.json")

        try writeSession(in: root, name: "a", daysAgo: 1)
        let service = SessionHistoryService(rootURL: root, cacheURL: cacheURL)
        _ = try await service.loadHistory(range: .thirtyDays)
        let first = try JSONDecoder().decode(HistoryCache.self, from: Data(contentsOf: cacheURL))

        _ = try await service.loadHistory(range: .thirtyDays)
        let second = try JSONDecoder().decode(HistoryCache.self, from: Data(contentsOf: cacheURL))
        #expect(second.entries.keys.sorted() == first.entries.keys.sorted())
        for (path, entry) in first.entries {
            #expect(second.entries[path]?.mtime == entry.mtime)
        }
    }
}

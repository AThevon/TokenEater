import Foundation

/// JSONL aggregator backing the History view. Designed to scale to hundreds of
/// session files without freezing the UI:
/// - mtime filter -> only scan files that could possibly contain data in the
///   requested range
/// - per-file persisted cache keyed by path + mtime -> repeated opens after
///   the first cold scan re-use the previous result and only re-parse the
///   handful of files that changed since
/// - line streaming via `enumerateLines` + `contains("input_tokens")` cheap
///   pre-filter -> JSON parse only the assistant turns that actually carry
///   token usage
/// - TaskGroup with concurrency cap -> uses cores without saturating
/// - cooperative cancellation via `Task.checkCancellation()`
final class SessionHistoryService: SessionHistoryServiceProtocol {

    /// Cache file path. Same dir as the shared usage file so it's easy
    /// to nuke during dev. Falls back to `NSHomeDirectory()` when the
    /// user domain isn't fully resolved (some CI / sandboxed envs).
    private static var cacheURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent("com.tokeneater.shared", isDirectory: true)
            .appendingPathComponent("history-cache.json")
    }

    /// Root scan dir. Real home, not the sandbox container -> we resolve via
    /// `getpwuid` (same trick used in `SharedFileService` for the widget).
    private static var projectsURL: URL {
        let pw = getpwuid(getuid())
        let home: URL
        if let home_str = pw?.pointee.pw_dir.flatMap({ String(cString: $0) }), !home_str.isEmpty {
            home = URL(fileURLWithPath: home_str)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }
        return home.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// 4 files in parallel keeps the work tight without saturating the IO
    /// queue or starving the rest of the app of cores.
    private static let concurrencyCap = 4

    enum Source: Sendable {
        case claude
        case codex
    }

    private let source: Source
    private let roots: [URL]
    private let persistedCacheURL: URL

    init(source: Source = .claude, rootURL: URL? = nil, cacheURL: URL? = nil) {
        self.source = source
        switch source {
        case .claude:
            roots = [rootURL ?? Self.projectsURL]
            persistedCacheURL = cacheURL ?? Self.cacheURL
        case .codex:
            let home = rootURL ?? CodexAuthReader().codexHomeURL
            roots = [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")]
            persistedCacheURL = cacheURL ?? Self.cacheURL.deletingLastPathComponent()
                .appendingPathComponent("codex-history-cache.json")
        }
    }

    // MARK: - Public

    func loadHistory(range: HistoryRange) async throws -> [HistoryBucket] {
        try await loadAggregates(rangeStart: rangeStart(for: range), bucketing: range)
    }

    func loadPreviousPeriodActiveTokens(range: HistoryRange) async throws -> Int {
        let now = Date()
        let currentStart = range == .sevenDays
            ? ChartDomainCalculator.domain(range: range, now: now).start
            : now.addingTimeInterval(-range.seconds)
        let previousStart = range == .sevenDays
            ? Calendar.current.date(byAdding: .day, value: -7, to: currentStart) ?? currentStart.addingTimeInterval(-range.seconds)
            : currentStart.addingTimeInterval(-range.seconds)
        let buckets = try await loadAggregates(
            rangeStart: previousStart,
            rangeEnd: currentStart,
            bucketing: range
        )
        return buckets.reduce(0) { $0 + $1.totalActive }
    }

    // MARK: - Aggregation pipeline

    private func loadAggregates(
        rangeStart: Date,
        rangeEnd: Date = Date(),
        bucketing: HistoryRange
    ) async throws -> [HistoryBucket] {
        // 1. List candidate files via FileManager + mtime filter.
        let files = try candidateFiles(rangeStart: rangeStart)
        try Task.checkCancellation()

        // 2. Load existing cache off the main queue (small JSON, cheap).
        var cache = loadCache()
        let source = self.source

        // 3. Parse each candidate file in a TaskGroup, hitting the cache when
        //    mtime matches. We collect cache entries so we can persist them
        //    back at the end of the run.
        var newEntries: [String: HistoryFileCacheEntry] = [:]
        try await withThrowingTaskGroup(of: HistoryFileCacheEntry?.self) { group in
            var inFlight = 0
            var iterator = files.makeIterator()

            // Prime the pump up to the concurrency cap.
            while inFlight < Self.concurrencyCap, let url = iterator.next() {
                group.addTask { try await Self.parseOrReuse(url: url, cache: cache, source: source) }
                inFlight += 1
            }

            while let result = try await group.next() {
                inFlight -= 1
                if let entry = result {
                    newEntries[entry.path] = entry
                }
                if let url = iterator.next() {
                    group.addTask { try await Self.parseOrReuse(url: url, cache: cache, source: source) }
                    inFlight += 1
                }
                try Task.checkCancellation()
            }
        }

        // 4. Merge new entries back into the cache and persist if anything
        //    changed.
        cache.entries = newEntries
        saveCache(cache)

        // 5. Aggregate across files into the requested bucketing.
        return Self.aggregate(
            entries: deduplicatedEntries(Array(newEntries.values)),
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            bucketing: bucketing
        )
    }

    // MARK: - File discovery

    private func candidateFiles(rangeStart: Date) throws -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else { continue }
                let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard attrs?.isRegularFile == true else { continue }
                // mtime filter: a file with mtime older than rangeStart cannot
                // possibly contain events relevant to the requested window. Skip.
                if let mtime = attrs?.contentModificationDate, mtime < rangeStart {
                    continue
                }
                results.append(url)
            }
        }
        return results
    }

    // MARK: - Per-file parsing

    private static func parseOrReuse(
        url: URL,
        cache: HistoryCache,
        source: Source
    ) async throws -> HistoryFileCacheEntry? {
        try Task.checkCancellation()

        let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let mtime = attrs?.contentModificationDate else { return nil }

        // Cache hit: same mtime -> reuse without touching disk.
        if let cached = cache.entries[url.path], cached.mtime == mtime {
            return cached
        }

        // Cache miss: stream the file line by line.
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return nil
        }

        if source == .codex {
            return try CodexHistoryParser.parse(content, path: url.path, mtime: mtime)
        }

        var bucketsByHour: [Date: HistoryBucket] = [:]
        var sessionIds: Set<String> = []

        content.enumerateLines { line, _ in
            // Cheap pre-filter: lines without token usage are ignored. Skips
            // user prompts, tool_use blocks, system messages, etc.
            guard line.contains("input_tokens") else { return }
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            // Timestamp -> bucket date (start of hour).
            guard let tsString = obj["timestamp"] as? String,
                  let date = isoDate(tsString) else { return }
            let bucketDate = startOfHour(date)

            // Session id -> contributes to the distinct count.
            if let sessionId = obj["sessionId"] as? String {
                sessionIds.insert(sessionId)
            }

            // Project path: prefer the per-event `cwd` field. The
            // directory-name decoding fallback is lossy for project paths
            // that contain hyphens (`/` -> `-` collapses `/a/b-c` and
            // `/a/b/c` to the same key).
            let projectPath: String
            if let cwd = obj["cwd"] as? String, !cwd.isEmpty {
                projectPath = cwd
            } else {
                projectPath = decodedProject(from: url)
            }

            // Pull message + usage payload.
            guard let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { return }

            let modelString = (message["model"] as? String) ?? ""
            let kind = ModelKind(rawModel: modelString)

            let input = (usage["input_tokens"] as? Int) ?? 0
            let output = (usage["output_tokens"] as? Int) ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
            let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
            let active = input + cacheCreate + output

            var bucket = bucketsByHour[bucketDate] ?? HistoryBucket(
                date: bucketDate,
                tokensByModel: [:],
                tokensByProject: [:],
                sessionsCount: 0,
                inputTokens: 0,
                outputTokens: 0,
                cacheReadTokens: 0,
                cacheCreateTokens: 0
            )
            bucket.tokensByModel[kind, default: 0] += active
            bucket.tokensByProject[projectPath, default: 0] += active
            bucket.inputTokens += input
            bucket.outputTokens += output
            bucket.cacheReadTokens += cacheRead
            bucket.cacheCreateTokens += cacheCreate
            bucketsByHour[bucketDate] = bucket
        }

        // Each file is a single session. The session-count contribution is 1
        // per *distinct* session id we observed. In practice that's always 1
        // for a JSONL file, but the format technically allows multiple ids
        // (resumes), so count properly.
        let sessions = max(1, sessionIds.count)
        var output = bucketsByHour
        // Distribute the file's session count across its earliest bucket so
        // the daily aggregator can sum without double-counting.
        if let earliest = output.keys.min() {
            output[earliest]?.sessionsCount = sessions
        }

        return HistoryFileCacheEntry(
            path: url.path,
            mtime: mtime,
            buckets: Array(output.values).sorted { $0.date < $1.date },
            sessionIds: Array(sessionIds)
        )
    }

    // MARK: - Aggregation across files

    private static func aggregate(
        entries: [HistoryFileCacheEntry],
        rangeStart: Date,
        rangeEnd: Date,
        bucketing: HistoryRange
    ) -> [HistoryBucket] {
        var combined: [Date: HistoryBucket] = [:]

        for entry in entries {
            for hourly in entry.buckets {
                guard hourly.date >= rangeStart, hourly.date < rangeEnd else { continue }
                let key = bucketing.isHourly ? hourly.date : startOfDay(hourly.date)
                let existing = combined[key] ?? HistoryBucket(
                    date: key,
                    tokensByModel: [:],
                    tokensByProject: [:],
                    sessionsCount: 0,
                    inputTokens: 0,
                    outputTokens: 0,
                    cacheReadTokens: 0,
                    cacheCreateTokens: 0
                )
                combined[key] = HistoryBucket.merging(existing, hourly, date: key)
            }
        }

        return combined.values.sorted { $0.date < $1.date }
    }

    private func deduplicatedEntries(_ entries: [HistoryFileCacheEntry]) -> [HistoryFileCacheEntry] {
        guard source == .codex else { return entries }
        var sessions: [String: HistoryFileCacheEntry] = [:]
        for entry in entries.sorted(by: { $0.mtime < $1.mtime }) {
            sessions[entry.sessionIds.first ?? entry.path] = entry
        }
        return Array(sessions.values)
    }

    // MARK: - Cache persistence

    private func loadCache() -> HistoryCache {
        guard let data = try? Data(contentsOf: persistedCacheURL),
              let cache = try? JSONDecoder().decode(HistoryCache.self, from: data),
              cache.isCurrentVersion
        else {
            return .empty
        }
        return cache
    }

    private func saveCache(_ cache: HistoryCache) {
        let url = persistedCacheURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Date helpers

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func isoDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    private static func startOfHour(_ date: Date) -> Date {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour], from: date)
        return Calendar.current.date(from: comps) ?? date
    }

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func rangeStart(for range: HistoryRange) -> Date {
        range == .sevenDays
            ? ChartDomainCalculator.domain(range: range).start
            : Date().addingTimeInterval(-range.seconds)
    }

    // MARK: - Project path decode

    /// Claude Code stores sessions under a directory whose name is the project
    /// path with `/` swapped for `-` (e.g. `/Users/foo/repo` becomes
    /// `-Users-foo-repo`). We re-form the path for display by reversing that
    /// substitution. Fallback to the raw directory name if anything fails.
    private static func decodedProject(from fileURL: URL) -> String {
        let dir = fileURL.deletingLastPathComponent().lastPathComponent
        guard dir.hasPrefix("-") else { return dir }
        let withSlashes = "/" + String(dir.dropFirst()).replacingOccurrences(of: "-", with: "/")
        return withSlashes
    }
}

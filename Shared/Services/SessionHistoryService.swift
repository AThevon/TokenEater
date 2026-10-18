import Foundation

/// JSONL aggregator backing the History view. Designed to scale to hundreds of
/// session files without freezing the UI:
/// - mtime filter -> only scan files that could possibly contain data in the
///   requested range
/// - per-file persisted cache keyed by path + mtime -> repeated opens after
///   the first cold scan re-use the previous result and only re-parse the
///   handful of files that changed since
/// - block-by-block streaming (`forEachLine`) + an `input_tokens` byte
///   pre-filter -> a transcript is never held whole in memory, and only the
///   assistant turns that actually carry token usage are JSON-parsed
/// - TaskGroup with concurrency cap -> uses cores without saturating
/// - cooperative cancellation via `Task.checkCancellation()`
final class SessionHistoryService: SessionHistoryServiceProtocol {

    /// Cache file path. Same dir as the shared usage file so it's easy
    /// to nuke during dev. Falls back to `NSHomeDirectory()` when the
    /// user domain isn't fully resolved (some CI / sandboxed envs).
    private static var cacheURL: URL { cacheURL(for: .main) }

    /// The cache of one Claude account's transcripts: `history-cache.json`
    /// for the main account, as it has always been, and
    /// `history-cache.acct-<uuid>.json` for an added one, so two folders
    /// never prune each other's entries. Paths and token counts only.
    static func cacheURL(for account: AccountID) -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent("com.tokeneater.shared", isDirectory: true)
            .appendingPathComponent("history-cache\(account.storageSuffix).json")
    }

    /// Where the main Claude account keeps its transcripts: `<dir>/projects`
    /// of the config folder the user chose for it, `~/.claude/projects` when
    /// they never chose one (#294). Real home, not the sandbox container, via
    /// `getpwuid` (same trick as `SharedFileService`). Read on every load,
    /// so moving the main account to another folder takes effect on the next
    /// History refresh without rebuilding anything.
    private static func mainProjectsURL() -> URL {
        ClaudeAccountsStorage.mainScope().projectsURL(home: ClaudeConfigDirResolver.realHome())
    }

    /// 4 files in parallel keeps the work tight without saturating the IO
    /// queue or starving the rest of the app of cores.
    private static let concurrencyCap = 4

    enum Source: Sendable {
        case claude
        case codex

        var provider: MetricProvider {
            switch self {
            case .claude: return .claude
            case .codex:  return .codex
            }
        }
    }

    private let source: Source
    /// The directories to scan, evaluated at every load. Only the files under
    /// them are aggregated, so entries the persisted cache still holds for a
    /// previous root never leak into the totals.
    private let rootsProvider: @Sendable () -> [URL]
    private let persistedCacheURL: URL

    /// - Parameters:
    ///   - rootURL: a fixed root (tests, or a known folder). Without it, Claude
    ///     follows the main account's config folder and Codex `CODEX_HOME`.
    ///   - rootsProvider: roots computed at each load, for tests that move
    ///     the root between two loads. Wins over `rootURL`.
    init(
        source: Source = .claude,
        rootURL: URL? = nil,
        cacheURL: URL? = nil,
        rootsProvider: (@Sendable () -> [URL])? = nil
    ) {
        self.source = source
        switch source {
        case .claude:
            if let rootsProvider {
                self.rootsProvider = rootsProvider
            } else if let rootURL {
                self.rootsProvider = { [rootURL] }
            } else {
                self.rootsProvider = { [Self.mainProjectsURL()] }
            }
            persistedCacheURL = cacheURL ?? Self.cacheURL
        case .codex:
            let home = rootURL ?? CodexAuthReader().codexHomeURL
            let roots = [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")]
            self.rootsProvider = rootsProvider ?? { roots }
            persistedCacheURL = cacheURL ?? Self.cacheURL.deletingLastPathComponent()
                .appendingPathComponent("codex-history-cache.json")
        }
    }

    // MARK: - Public

    func loadHistory(range: HistoryRange) async throws -> [HistoryBucket] {
        try await loadAggregates(rangeStart: rangeStart(for: range), bucketing: range)
    }

    func loadPreviousPeriodActiveTokens(range: HistoryRange) async throws -> [MetricProvider: Int] {
        let now = Date()
        let currentStart = range == .sevenDays
            ? ChartDomainCalculator.domain(range: range, now: now).start
            : now.addingTimeInterval(-range.seconds)
        // Both windows must span the same duration or the delta reports a
        // decline that is only a difference in length. The 7-day domain starts
        // at midnight six days ago, so the current window runs 6.0 to 7.0 days
        // depending on the time of day; a flat -7d previous window made the
        // hero card read about -14% at 00:30 on perfectly steady usage.
        let previousStart = range == .sevenDays
            ? currentStart.addingTimeInterval(-now.timeIntervalSince(currentStart))
            : currentStart.addingTimeInterval(-range.seconds)
        let buckets = try await loadAggregates(
            rangeStart: previousStart,
            rangeEnd: currentStart,
            bucketing: range
        )
        return [source.provider: buckets.reduce(0) { $0 + $1.totalActive }]
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
        let cache = loadCache()
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

        // 4. Merge new entries back into the cache and persist.
        //
        //    This used to be `cache.entries = newEntries`, which looked tidy
        //    and quietly evicted every file the current range could not see.
        //    The mtime filter in step 1 drops anything older than rangeStart,
        //    so a 7-day scan rewrote the cache with only the last week's
        //    files and a following 30-day scan re-parsed everything from
        //    scratch. Since `MonitoringInsightsStore` (current window plus
        //    previous window), `HistoryWidgetStore` and the History view all
        //    scan with different ranges, the cache spent its life being
        //    rebuilt and the expensive cold parse never stopped happening.
        //
        //    Re-read immediately before writing rather than reusing the copy
        //    taken in step 2: several scans run concurrently, and the shared
        //    file next door needs the same read-modify-write discipline for
        //    the same reason. Then merge, and prune only what has actually
        //    disappeared from disk, so the cache still cannot grow forever.
        var persisted = loadCache()
        persisted.entries.merge(newEntries) { _, fresh in fresh }
        persisted.entries = persisted.entries.filter {
            FileManager.default.fileExists(atPath: $0.key)
        }
        saveCache(persisted)

        // A scan frees its read buffers at once, but malloc keeps the large
        // ones dirty for tens of seconds before handing them back, which is
        // what Activity Monitor shows. Give them back now.
        malloc_zone_pressure_relief(nil, 0)

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

        for root in rootsProvider() {
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

        if source == .codex {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return try CodexHistoryParser.parse(content, path: url.path, mtime: mtime)
        }

        // Cache miss: stream the file in blocks rather than reading it whole.
        // A Claude Code transcript can weigh tens of megabytes, four parse at
        // once, and a whole-file `String` per file is what pushed a cold
        // launch past 900 MB. Only lines carrying token usage are decoded.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var bucketsByHour: [Date: HistoryBucket] = [:]
        var sessionIds: Set<String> = []

        // A read that fails partway (an I/O error, a cloud file not yet
        // downloaded) skips this transcript, as the whole-file read it
        // replaced did, rather than failing the History scan of every file.
        let read: Void? = try skippingUnreadable {
            try forEachLine(in: handle, containing: usageMarker) { data in
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
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
        }
        guard read != nil else { return nil }

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

    /// The bytes a JSONL line must hold to be worth decoding: lines without
    /// token usage (prompts, tool calls, system messages) are skipped unread.
    private static let usageMarker = Data("input_tokens".utf8)

    /// Runs one transcript's read, turning any failure but cancellation into
    /// nil, so one unreadable file is skipped instead of ending the scan.
    static func skippingUnreadable<T>(_ read: () throws -> T) throws -> T? {
        do {
            return try read()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    /// Size of each read. Bounds what one file holds in memory at a time,
    /// whatever its length.
    private static let readChunkSize = 1 << 20

    /// Calls `body` with each newline-terminated line of `handle` (the last
    /// one too when it has no newline) that contains `marker`, reading one
    /// block at a time. Lines are split on `\n` only: a JSONL record never
    /// holds a raw newline, while a Unicode line separator can sit inside one
    /// of its strings.
    static func forEachLine(
        in handle: FileHandle,
        containing marker: Data,
        _ body: (Data) throws -> Void
    ) throws {
        var pending = Data()
        // How much of `pending` is already known to hold no newline. A line
        // longer than one block is searched once, not again from its start
        // with each block it grows by: a line of tens of megabytes (a large
        // tool output, an image in base64) then cost quadratic time.
        var scanned = 0
        while true {
            try Task.checkCancellation()
            let chunk = try autoreleasepool { try handle.read(upToCount: readChunkSize) ?? Data() }
            if chunk.isEmpty { break }
            pending.append(chunk)
            var start = 0
            var searchFrom = scanned
            while let newline = newlineOffset(in: pending, from: searchFrom) {
                let line = pending.subdata(in: start..<newline)
                if line.range(of: marker) != nil { try body(line) }
                start = newline + 1
                searchFrom = start
            }
            // Only the unfinished line is carried over, and only copied when
            // something before it was consumed.
            if start > 0 { pending = pending.subdata(in: start..<pending.count) }
            scanned = pending.count
        }
        if !pending.isEmpty, pending.range(of: marker) != nil { try body(pending) }
    }

    /// The offset of the first `\n` in `data` at or after `offset`, found
    /// with `memchr` rather than a byte-by-byte collection walk. `data`
    /// starts at index 0, which `forEachLine` keeps true.
    private static func newlineOffset(in data: Data, from offset: Int) -> Int? {
        guard offset < data.count else { return nil }
        return data.withUnsafeBytes { raw -> Int? in
            guard let base = raw.baseAddress,
                  let hit = memchr(base + offset, 0x0A, raw.count - offset) else { return nil }
            return base.distance(to: UnsafeRawPointer(hit))
        }
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

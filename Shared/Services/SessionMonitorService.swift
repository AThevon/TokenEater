import Foundation
import Combine

final class SessionMonitorService: SessionMonitorServiceProtocol, @unchecked Sendable {
    private let sessionsSubject = CurrentValueSubject<[ClaudeSession], Never>([])
    var sessionsPublisher: AnyPublisher<[ClaudeSession], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.tokeneater.session-monitor", qos: .utility)
    // Mutated only on `queue` (see setScanInterval/setVisibility) so they stay
    // race-free despite the @unchecked Sendable conformance.
    private var scanInterval: TimeInterval
    private var projectDirFreshness: TimeInterval
    private let claudeProjectsDirOverride: URL?
    private let claudeSessionsDirOverride: URL?
    private let processProvider: @Sendable () -> [ClaudeProcessInfo]

    // Cross-tick caches (#255). All three are touched only inside `scan()`,
    // which runs on `queue` in production and synchronously (never
    // concurrently) in tests, so they need no extra locking.

    /// Per-project-dir file listing keyed by dir path. On APFS/HFS a dir's
    /// mtime changes on add/remove/rename but NOT when a contained file is
    /// appended to, so an unchanged dir mtime proves the file LIST is
    /// unchanged and re-enumerating thousands of JSONLs every tick is pure
    /// waste. File mtimes are deliberately NOT part of this cache: appends
    /// move them without touching the dir, so they are re-stat'ed fresh
    /// wherever they matter.
    private struct DirListing {
        let dirMtime: Date
        let files: [(url: URL, sessionId: String)]
    }
    private var dirListings: [String: DirListing] = [:]

    /// First-line timestamp per transcript path. Transcripts are append-only,
    /// so a first line never changes once it exists and parses.
    private var startedAtCache: [String: Date] = [:]

    /// A file identity snapshot for cache validity: mtime plus size. Size
    /// matters on volumes with 1-2s mtime granularity (HFS+, SMB) where two
    /// appends can share a timestamp; an append always grows the file.
    private struct FileStamp: Equatable {
        let mtime: Date
        let size: Int
    }

    /// Last tail-parse per transcript path, valid while the file's stamp is
    /// unchanged: appends are the only mutation Claude Code performs on a
    /// transcript.
    private var parseCache: [String: (stamp: FileStamp, result: JSONLParseResult)] = [:]

    private var claudeProjectsDir: URL {
        if let override = claudeProjectsDirOverride { return override }
        let home: String
        if let pw = getpwuid(getuid()) {
            home = String(cString: pw.pointee.pw_dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home).appendingPathComponent(".claude/projects")
    }

    private var claudeSessionsDir: URL {
        if let override = claudeSessionsDirOverride { return override }
        let home: String
        if let pw = getpwuid(getuid()) {
            home = String(cString: pw.pointee.pw_dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home).appendingPathComponent(".claude/sessions")
    }

    init(
        scanInterval: TimeInterval = 2.0,
        projectDirFreshness: TimeInterval = 30 * 60,
        claudeProjectsDirOverride: URL? = nil,
        claudeSessionsDirOverride: URL? = nil,
        processProvider: @escaping @Sendable () -> [ClaudeProcessInfo] = { ProcessResolver.findClaudeProcesses() }
    ) {
        self.scanInterval = scanInterval
        self.projectDirFreshness = projectDirFreshness
        self.claudeProjectsDirOverride = claudeProjectsDirOverride
        self.claudeSessionsDirOverride = claudeSessionsDirOverride
        self.processProvider = processProvider
    }

    func startMonitoring() {
        queue.async { [weak self] in self?.startTimerLocked() }
    }

    func stopMonitoring() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.sessionsSubject.send([])
        }
    }

    /// Builds (or rebuilds) the repeating scan timer. MUST run on `queue`,
    /// which owns `timer`, `scanInterval` and `projectDirFreshness`.
    private func startTimerLocked() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: scanInterval)
        timer.setEventHandler { [weak self] in
            self?.scan()
        }
        timer.resume()
        self.timer = timer
    }

    /// Change the scan cadence at runtime. Rebuilds the live timer when
    /// monitoring is active; otherwise the new value is picked up by the next
    /// `startMonitoring`. Routed through `queue` to stay ordered with start/stop.
    func setScanInterval(_ interval: TimeInterval) {
        queue.async { [weak self] in
            guard let self, interval != self.scanInterval else { return }
            self.scanInterval = interval
            if self.timer != nil { self.startTimerLocked() }
        }
    }

    /// Change how long a cold session stays inside the scan window at runtime.
    func setVisibility(_ freshness: TimeInterval) {
        queue.async { [weak self] in
            self?.projectDirFreshness = freshness
        }
    }

    /// Internal for tests, which call it synchronously on a service whose
    /// timer never runs. It mutates the cross-tick caches, so it must never
    /// run concurrently with a live monitoring timer; production always runs
    /// it on `queue`.
    func scan() {
        let processes = processProvider()
        guard !processes.isEmpty else {
            sessionsSubject.send([])
            return
        }

        let fm = FileManager.default
        let projectsDir = claudeProjectsDir

        guard fm.fileExists(atPath: projectsDir.path) else {
            sessionsSubject.send([])
            return
        }

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            sessionsSubject.send([])
            return
        }

        // Authoritative pid -> session mapping from Claude Code's registry
        // (`~/.claude/sessions/<pid>.json`), for the running pids only.
        let registry = readSessionRegistry(pids: Set(processes.map { $0.pid }))

        refreshDirListings(projectDirs: projectDirs, fm: fm)

        // Resolve a transcript for each sessionId the registry names, and only
        // those: the cached listings already say where a "<sessionId>.jsonl"
        // lives, so a handful of fresh stats replaces the every-file mtime
        // sweep the old full index paid on each tick (#255). A transcript
        // resolves wherever it lives, which is how a `--resume`d session whose
        // transcript sits under its ORIGINAL project dir, not the directory
        // the process was launched from, is found (#233). When the same
        // sessionId exists under several dirs, the newest mtime wins (dirs are
        // walked in stable path order so equal-mtime ties cannot flap between
        // ticks with the dictionary's hashing).
        struct TranscriptRef { let url: URL; let stamp: FileStamp; let dir: URL }
        var neededSids = Set<String>()
        for proc in processes {
            if let sid = registry[proc.pid]?.sessionId { neededSids.insert(sid) }
        }
        var bySessionId: [String: TranscriptRef] = [:]
        if !neededSids.isEmpty {
            bySessionId.reserveCapacity(neededSids.count)
            for (dirPath, listing) in dirListings.sorted(by: { $0.key < $1.key }) {
                for entry in listing.files where neededSids.contains(entry.sessionId) {
                    let stamp = fileStamp(atPath: entry.url.path, fm: fm)
                    if let existing = bySessionId[entry.sessionId], existing.stamp.mtime >= stamp.mtime { continue }
                    bySessionId[entry.sessionId] = TranscriptRef(
                        url: entry.url,
                        stamp: stamp,
                        dir: URL(fileURLWithPath: dirPath, isDirectory: true)
                    )
                }
            }
        }

        var activeSessions: [ClaudeSession] = []
        var consumedPids = Set<Int32>()
        var emittedSessionIds = Set<String>()

        // PRIMARY pass: registry-driven. A running process tells us its exact
        // sessionId, so we render THAT transcript instead of guessing by
        // working directory. No freshness gate here: the process is provably
        // alive, so its session is live even if idle for a while.
        for proc in processes {
            guard let entry = registry[proc.pid],
                  let sid = entry.sessionId,
                  let ref = bySessionId[sid],
                  let result = cachedReadAndParse(file: ref.url, stamp: ref.stamp) else { continue }

            let startedAt = cachedStartedAt(of: ref.url) ?? ref.stamp.mtime
            let resolvedState: SessionState
            if result.state == .thinking,
               let compactState = checkCompacting(sessionId: sid, projectDir: ref.dir) {
                resolvedState = compactState
            } else {
                resolvedState = result.state
            }
            activeSessions.append(ClaudeSession(
                id: sid,
                projectPath: result.projectPath,
                gitBranch: result.gitBranch,
                userSessionName: userName(from: entry, sessionId: sid),
                model: result.model,
                state: resolvedState,
                lastUpdate: ref.stamp.mtime,
                startedAt: startedAt,
                processPid: proc.pid,
                sourceKind: proc.sourceKind,
                transcriptPath: ref.url.path,
                contextTokens: result.contextTokens,
                contextMax: result.contextMax
            ))
            consumedPids.insert(proc.pid)
            emittedSessionIds.insert(sid)
        }

        // FALLBACK pass: the pre-registry heuristic for any process without a
        // usable registry entry (older Claude Code, or a transcript we could
        // not locate) - match by working directory, newest transcript first,
        // over fresh dirs only.
        let remaining = processes.filter { !consumedPids.contains($0.pid) }
        if !remaining.isEmpty {
            // The full per-file stat sweep is paid only here, when a process
            // has no usable registry entry (older Claude Code, or a transcript
            // the registry pass could not locate).
            var dirFiles: [(dir: URL, files: [(url: URL, stamp: FileStamp)])] = []
            dirFiles.reserveCapacity(dirListings.count)
            for (dirPath, listing) in dirListings.sorted(by: { $0.key < $1.key }) where !listing.files.isEmpty {
                var files: [(url: URL, stamp: FileStamp)] = []
                files.reserveCapacity(listing.files.count)
                for entry in listing.files {
                    files.append((entry.url, fileStamp(atPath: entry.url.path, fm: fm)))
                }
                dirFiles.append((URL(fileURLWithPath: dirPath, isDirectory: true), files))
            }

            var cwdToProcesses: [String: [ClaudeProcessInfo]] = [:]
            for proc in remaining {
                cwdToProcesses[proc.cwd, default: []].append(proc)
                if let range = proc.cwd.range(of: "/.claude/worktrees/") {
                    let canonical = String(proc.cwd[proc.cwd.startIndex..<range.lowerBound])
                    cwdToProcesses[canonical, default: []].append(proc)
                }
            }

            let freshnessCutoff = Date().addingTimeInterval(-projectDirFreshness)
            // Longer dir paths first so worktree-specific dirs match before parent projects.
            let sortedDirs = dirFiles.sorted { $0.dir.lastPathComponent.count > $1.dir.lastPathComponent.count }

            outer: for entry in sortedDirs {
                let sortedFiles = entry.files.sorted { $0.stamp.mtime > $1.stamp.mtime }
                guard let newest = sortedFiles.first, newest.stamp.mtime >= freshnessCutoff else { continue }

                for (file, stamp) in sortedFiles {
                    let sessionId = file.deletingPathExtension().lastPathComponent
                    if emittedSessionIds.contains(sessionId) { continue }
                    guard let result = cachedReadAndParse(file: file, stamp: stamp) else { continue }
                    guard let process = matchProcess(projectPath: result.projectPath, in: cwdToProcesses) else { continue }

                    let startedAt = cachedStartedAt(of: file) ?? stamp.mtime
                    let resolvedState: SessionState
                    if result.state == .thinking,
                       let compactState = checkCompacting(sessionId: sessionId, projectDir: entry.dir) {
                        resolvedState = compactState
                    } else {
                        resolvedState = result.state
                    }
                    activeSessions.append(ClaudeSession(
                        id: sessionId,
                        projectPath: result.projectPath,
                        gitBranch: result.gitBranch,
                        userSessionName: readUserSessionName(pid: process.pid, sessionId: sessionId),
                        model: result.model,
                        state: resolvedState,
                        lastUpdate: stamp.mtime,
                        startedAt: startedAt,
                        processPid: process.pid,
                        sourceKind: process.sourceKind,
                        transcriptPath: file.path,
                        contextTokens: result.contextTokens,
                        contextMax: result.contextMax
                    ))
                    emittedSessionIds.insert(sessionId)

                    let matchedPid = process.pid
                    for (key, procs) in cwdToProcesses {
                        let filtered = procs.filter { $0.pid != matchedPid }
                        if filtered.isEmpty {
                            cwdToProcesses.removeValue(forKey: key)
                        } else {
                            cwdToProcesses[key] = filtered
                        }
                    }
                    if cwdToProcesses.isEmpty { break outer }
                }
            }
        }

        activeSessions.sort {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.id < $1.id
        }
        sessionsSubject.send(activeSessions)
    }

    /// Refresh the per-dir listing cache from a fresh top-level listing of
    /// the projects dir. Only dirs whose mtime moved since the last tick are
    /// re-enumerated; listings of deleted dirs are dropped, and the per-file
    /// caches of files that left a listing are purged with them.
    private func refreshDirListings(projectDirs: [URL], fm: FileManager) {
        var live = Set<String>()
        live.reserveCapacity(projectDirs.count)
        for dir in projectDirs where dir.hasDirectoryPath {
            let path = dir.path
            live.insert(path)
            let dirMtime = (try? dir.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            // Serve the cache only when the mtime is readable, matches, and is
            // safely in the past: an unreadable mtime can hide anything, and a
            // just-modified dir could still gain a file inside the same
            // timestamp bucket on volumes with 1-2s mtime granularity (HFS+,
            // SMB).
            if dirMtime != .distantPast,
               Date().timeIntervalSince(dirMtime) > 2,
               let cached = dirListings[path], cached.dirMtime == dirMtime { continue }
            // A failed enumeration must never be cached as an empty listing:
            // recovering read permission changes ctime, not mtime, so the
            // entry would never invalidate and the dir's sessions would stay
            // invisible. Drop the entry and retry next tick, matching the
            // pre-cache behavior of skipping such a dir for one tick only.
            guard let urls = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                purgeFileCaches(for: dirListings.removeValue(forKey: path))
                continue
            }
            var files: [(url: URL, sessionId: String)] = []
            files.reserveCapacity(urls.count)
            for url in urls where url.pathExtension == "jsonl" {
                files.append((url, url.deletingPathExtension().lastPathComponent))
            }
            if let old = dirListings[path] {
                let kept = Set(files.map { $0.url.path })
                for entry in old.files where !kept.contains(entry.url.path) {
                    parseCache.removeValue(forKey: entry.url.path)
                    startedAtCache.removeValue(forKey: entry.url.path)
                }
            }
            dirListings[path] = DirListing(dirMtime: dirMtime, files: files)
        }
        if dirListings.count != live.count {
            for (path, listing) in dirListings where !live.contains(path) {
                purgeFileCaches(for: listing)
            }
            dirListings = dirListings.filter { live.contains($0.key) }
        }
    }

    /// Forget the per-file cache entries of a listing whose files left the
    /// scan (dir deleted, or enumeration failed); a recreated file at the same
    /// path must not inherit a dead file's parse or start timestamp.
    private func purgeFileCaches(for listing: DirListing?) {
        guard let listing else { return }
        for entry in listing.files {
            parseCache.removeValue(forKey: entry.url.path)
            startedAtCache.removeValue(forKey: entry.url.path)
        }
    }

    /// Fresh stat, bypassing NSURL's per-instance resource-value cache (the
    /// listing cache reuses URL instances across ticks, whose cached values
    /// would go stale).
    private func fileStamp(atPath path: String, fm: FileManager) -> FileStamp {
        guard let attrs = try? fm.attributesOfItem(atPath: path) else {
            return FileStamp(mtime: .distantPast, size: -1)
        }
        return FileStamp(
            mtime: (attrs[.modificationDate] as? Date) ?? .distantPast,
            size: (attrs[.size] as? Int) ?? -1
        )
    }

    /// First-line timestamp of a transcript, memoized per path: the file is
    /// append-only, so its first line never changes. A nil parse is not
    /// cached (the first line of a brand-new file may still be partial).
    private func cachedStartedAt(of url: URL) -> Date? {
        if let hit = startedAtCache[url.path] { return hit }
        guard let ts = readFirstTimestamp(of: url) else { return nil }
        if startedAtCache.count >= 8192 { startedAtCache.removeAll(keepingCapacity: true) }
        startedAtCache[url.path] = ts
        return ts
    }

    /// Tail-parse a transcript, reusing the previous tick's result while the
    /// file's stamp (mtime + size) is unchanged: no append happened, so the
    /// tail is identical. A failed stat (.distantPast sentinel) is never
    /// trusted as a cache key, in either direction.
    private func cachedReadAndParse(file: URL, stamp: FileStamp) -> JSONLParseResult? {
        let key = file.path
        if stamp.mtime != .distantPast,
           let hit = parseCache[key], hit.stamp == stamp {
            return hit.result
        }
        guard let result = readAndParse(file: file) else { return nil }
        if stamp.mtime == .distantPast { return result }
        // Real eviction happens when a file leaves its dir listing (see
        // purgeFileCaches), so the population is bounded by the transcripts on
        // disk; the cap is only a backstop, and it must stay above any
        // realistic transcript count or a full fallback sweep would wipe the
        // cache mid-scan and thrash (#255 reports ~7000 transcripts).
        if parseCache.count >= 8192 { parseCache.removeAll(keepingCapacity: true) }
        parseCache[key] = (stamp, result)
        return result
    }

    /// Match a JSONL project path to a running Claude process.
    /// Exact match first, then worktree-aware match (CWD is inside projectPath/.claude/worktrees/).
    private func matchProcess(projectPath: String, in lookup: [String: [ClaudeProcessInfo]]) -> ClaudeProcessInfo? {
        if let proc = lookup[projectPath]?.first { return proc }

        for (cwd, procs) in lookup {
            guard let proc = procs.first else { continue }
            if cwd.hasPrefix(projectPath + "/.claude/worktrees/") {
                return proc
            }
            if projectPath.hasPrefix(cwd + "/.claude/worktrees/") {
                return proc
            }
        }

        return nil
    }

    /// Read the user-set session name from Claude Code's session registry
    /// (`~/.claude/sessions/<pid>.json`). Called on every scan tick so a
    /// mid-session `/rename` is picked up at the next watcher refresh.
    /// Returns nil unless the entry's sessionId matches (guards against a
    /// stale file left behind by a dead process whose pid was reused) and the
    /// name was set by the user - auto-derived names like `myproject-01` are
    /// less informative than the branch/project fallback and are ignored.
    /// "User-set" means nameSource is "user" OR absent: Claude Code 2.1.202
    /// writes `nameSource: "derived"` for auto names but drops the field
    /// entirely after a /rename, so only an explicit derived/auto marker
    /// disqualifies the name.
    /// Decoded shape of a `~/.claude/sessions/<pid>.json` registry entry.
    private struct SessionRegistryEntry: Decodable {
        let sessionId: String?
        let name: String?
        let nameSource: String?
    }

    private func readUserSessionName(pid: Int32, sessionId: String) -> String? {
        let file = claudeSessionsDir.appendingPathComponent("\(pid).json")
        guard let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(SessionRegistryEntry.self, from: data) else {
            return nil
        }
        return userName(from: entry, sessionId: sessionId)
    }

    /// Load the session registry entries for the given running pids, keyed by
    /// pid. Each `<pid>.json` carries the exact `sessionId` the process is on,
    /// which is what lets the scan pick the right transcript for a `--resume`d
    /// session instead of guessing by working directory (#233).
    private func readSessionRegistry(pids: Set<Int32>) -> [Int32: SessionRegistryEntry] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: claudeSessionsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var out: [Int32: SessionRegistryEntry] = [:]
        for file in files where file.pathExtension == "json" {
            guard let pid = Int32(file.deletingPathExtension().lastPathComponent),
                  pids.contains(pid),
                  let data = try? Data(contentsOf: file),
                  let entry = try? JSONDecoder().decode(SessionRegistryEntry.self, from: data) else { continue }
            out[pid] = entry
        }
        return out
    }

    /// The user-set session name from a registry entry, or nil. Valid only when
    /// the entry's sessionId matches (guards against a stale file left by a
    /// dead process whose pid was reused) and the name was user-set: auto
    /// names like `myproject-01` are less informative than the branch/project
    /// fallback and are ignored. "User-set" means nameSource is "user" OR
    /// absent: Claude Code 2.1.202 writes `nameSource: "derived"` for auto
    /// names but drops the field entirely after a `/rename`, so only an
    /// explicit derived/auto marker disqualifies the name.
    private func userName(from entry: SessionRegistryEntry, sessionId: String) -> String? {
        guard entry.sessionId == sessionId,
              entry.nameSource == nil || entry.nameSource == "user",
              let name = entry.name, !name.isEmpty else {
            return nil
        }
        return name
    }

    /// Check if a session is currently compacting by looking for active `agent-acompact-*.jsonl` files.
    private func checkCompacting(sessionId: String, projectDir: URL) -> SessionState? {
        let fm = FileManager.default
        let subagentsDir = projectDir.appendingPathComponent(sessionId).appendingPathComponent("subagents")

        guard fm.fileExists(atPath: subagentsDir.path) else { return nil }

        guard let files = try? fm.contentsOfDirectory(atPath: subagentsDir.path) else { return nil }

        let now = Date()
        for file in files where file.hasPrefix("agent-acompact-") && file.hasSuffix(".jsonl") {
            let filePath = subagentsDir.appendingPathComponent(file).path
            if let attrs = try? fm.attributesOfItem(atPath: filePath),
               let modDate = attrs[.modificationDate] as? Date,
               now.timeIntervalSince(modDate) < 15 {
                return .compacting
            }
        }

        return nil
    }

    /// Adaptive tail read: start small (2KB), grow up to 64KB if parsing fails.
    /// Also retries with a larger tail when the parse succeeded but context
    /// token usage is missing - on long sessions a single assistant message
    /// can exceed 2KB on its own, so the smallest tail slice may only contain
    /// a system/progress event and miss the usage data we need for the
    /// context window indicator. We keep the last successful parse around as
    /// a fallback so truly brand-new sessions (zero assistant turns) still
    /// get a state.
    private func readAndParse(file: URL) -> JSONLParseResult? {
        var lastResult: JSONLParseResult?
        for size in [2_048, 8_192, 32_768, 65_536] {
            guard let content = readTail(of: file, maxBytes: size),
                  let result = JSONLParser.parseLastState(from: content) else {
                continue
            }
            lastResult = result
            if result.contextTokens != nil { return result }
        }
        return lastResult
    }

    private func readTail(of url: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let offset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()

        guard var content = String(data: data, encoding: .utf8) else { return nil }

        if offset > 0, let firstNewline = content.firstIndex(of: "\n") {
            content = String(content[content.index(after: firstNewline)...])
        }

        return content
    }

    private func readFirstTimestamp(of url: URL) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: 2048)
        guard let content = String(data: data, encoding: .utf8),
              let firstLine = content.split(separator: "\n", maxSplits: 1).first,
              let lineData = firstLine.data(using: .utf8) else { return nil }

        struct TimestampOnly: Decodable { let timestamp: String? }
        guard let parsed = try? JSONDecoder().decode(TimestampOnly.self, from: lineData),
              let ts = parsed.timestamp else { return nil }

        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: ts)
    }
}

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

    /// Internal for perf tests. Must stay safe to call synchronously off the timer queue.
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

        // Index every transcript once (filenames + mtime, no content reads).
        // A transcript is named "<sessionId>.jsonl", so this maps a sessionId
        // to its file wherever it lives - which is how we resolve a `--resume`d
        // session whose transcript sits under its ORIGINAL project dir, not the
        // directory the process happened to be launched from (#233).
        //
        // Freshness note: mtime comes from each JSONL, not the dir's own mtime.
        // On APFS/HFS a dir's mtime only changes on add/remove/rename, not when
        // Claude appends to an existing JSONL, so dir mtime would hide every
        // ongoing conversation. Reading cached URLResourceValues here stays
        // cheap versus `readAndParse()` per file.
        struct TranscriptRef { let url: URL; let mtime: Date; let dir: URL }
        var bySessionId: [String: TranscriptRef] = [:]
        var dirFiles: [(dir: URL, files: [(url: URL, mtime: Date)])] = []
        for dir in projectDirs where dir.hasDirectoryPath {
            guard let urls = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            var files: [(url: URL, mtime: Date)] = []
            for url in urls where url.pathExtension == "jsonl" {
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                files.append((url, mtime))
                let sid = url.deletingPathExtension().lastPathComponent
                if let existing = bySessionId[sid], existing.mtime >= mtime { continue }
                bySessionId[sid] = TranscriptRef(url: url, mtime: mtime, dir: dir)
            }
            if !files.isEmpty { dirFiles.append((dir, files)) }
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
                  let result = readAndParse(file: ref.url) else { continue }

            let startedAt = readFirstTimestamp(of: ref.url) ?? ref.mtime
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
                lastUpdate: ref.mtime,
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
                let sortedFiles = entry.files.sorted { $0.mtime > $1.mtime }
                guard let newest = sortedFiles.first, newest.mtime >= freshnessCutoff else { continue }

                for (file, mtime) in sortedFiles {
                    let sessionId = file.deletingPathExtension().lastPathComponent
                    if emittedSessionIds.contains(sessionId) { continue }
                    guard let result = readAndParse(file: file) else { continue }
                    guard let process = matchProcess(projectPath: result.projectPath, in: cwdToProcesses) else { continue }

                    let startedAt = readFirstTimestamp(of: file) ?? mtime
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
                        lastUpdate: mtime,
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

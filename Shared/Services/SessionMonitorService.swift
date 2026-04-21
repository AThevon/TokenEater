import Foundation
import Combine

final class SessionMonitorService: SessionMonitorServiceProtocol, @unchecked Sendable {
    private let sessionsSubject = CurrentValueSubject<[ClaudeSession], Never>([])
    var sessionsPublisher: AnyPublisher<[ClaudeSession], Never> {
        sessionsSubject.eraseToAnyPublisher()
    }

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.tokeneater.session-monitor", qos: .utility)
    private let scanInterval: TimeInterval
    private let projectDirFreshness: TimeInterval
    private let claudeProjectsDirOverride: URL?
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

    init(
        scanInterval: TimeInterval = 2.0,
        projectDirFreshness: TimeInterval = 30 * 60,
        claudeProjectsDirOverride: URL? = nil,
        processProvider: @escaping @Sendable () -> [ClaudeProcessInfo] = { ProcessResolver.findClaudeProcesses() }
    ) {
        self.scanInterval = scanInterval
        self.projectDirFreshness = projectDirFreshness
        self.claudeProjectsDirOverride = claudeProjectsDirOverride
        self.processProvider = processProvider
    }

    func startMonitoring() {
        timer?.cancel()
        timer = nil

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: scanInterval)
        timer.setEventHandler { [weak self] in
            self?.scan()
        }
        timer.resume()
        self.timer = timer
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
        sessionsSubject.send([])
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

        var cwdToProcesses: [String: [ClaudeProcessInfo]] = [:]
        for proc in processes {
            cwdToProcesses[proc.cwd, default: []].append(proc)
            if let range = proc.cwd.range(of: "/.claude/worktrees/") {
                let canonical = String(proc.cwd[proc.cwd.startIndex..<range.lowerBound])
                cwdToProcesses[canonical, default: []].append(proc)
            }
        }

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            sessionsSubject.send([])
            return
        }

        var activeSessions: [ClaudeSession] = []

        // Freshness is derived from each dir's newest JSONL mtime - NOT from the dir's own
        // mtime. On APFS/HFS, a directory's mtime only changes when an entry is added, removed,
        // or renamed: appending to an existing JSONL (what Claude Code does on every message
        // of an ongoing conversation) does not touch the parent dir's mtime. Filtering on dir
        // mtime therefore hides every session whose JSONL already existed when the 30-min
        // window started, which is most of them. We still get the original perf benefit (skip
        // reading file contents for dead projects) because listing a dir with cached
        // URLResourceValues is cheap compared to `readAndParse()` on every JSONL.
        let freshnessCutoff = Date().addingTimeInterval(-projectDirFreshness)
        let sortedDirs = projectDirs
            .filter { $0.hasDirectoryPath }
            // Process longer paths first so worktree-specific dirs match before parent project dirs.
            .sorted { $0.lastPathComponent.count > $1.lastPathComponent.count }

        for dir in sortedDirs {
            // Decorate-sort-undecorate: read each JSONL's mtime exactly once via the cached
            // URLResourceValues populated by `includingPropertiesForKeys`. The previous
            // implementation called `attributesOfItem(atPath:)` inside the sort comparator,
            // which ran 2 * O(N log N) syscalls per dir and dominated CPU at steady state.
            let jsonlFiles: [(url: URL, mtime: Date)]
            do {
                let urls = try fm.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ).filter { $0.pathExtension == "jsonl" }

                jsonlFiles = urls.map { url in
                    let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? .distantPast
                    return (url, mtime)
                }
            } catch { continue }

            let sortedFiles = jsonlFiles.sorted { $0.mtime > $1.mtime }

            // Skip dirs whose newest JSONL is stale. This replaces the old dir-mtime filter
            // and is the actual signal of "any session here was active recently".
            guard let newest = sortedFiles.first, newest.mtime >= freshnessCutoff else { continue }

            for (file, mtime) in sortedFiles {
                guard let result = readAndParse(file: file) else { continue }

                guard let process = matchProcess(projectPath: result.projectPath, in: cwdToProcesses) else { continue }

                let sessionId = file.deletingPathExtension().lastPathComponent
                let startedAt = readFirstTimestamp(of: file) ?? mtime

                let resolvedState: SessionState
                if result.state == .thinking,
                   let compactState = checkCompacting(sessionId: sessionId, projectDir: dir) {
                    resolvedState = compactState
                } else {
                    resolvedState = result.state
                }

                let session = ClaudeSession(
                    id: sessionId,
                    projectPath: result.projectPath,
                    gitBranch: result.gitBranch,
                    model: result.model,
                    state: resolvedState,
                    lastUpdate: mtime,
                    startedAt: startedAt,
                    processPid: process.pid,
                    sourceKind: process.sourceKind
                )
                activeSessions.append(session)

                let matchedPid = process.pid
                for (key, procs) in cwdToProcesses {
                    let filtered = procs.filter { $0.pid != matchedPid }
                    if filtered.isEmpty {
                        cwdToProcesses.removeValue(forKey: key)
                    } else {
                        cwdToProcesses[key] = filtered
                    }
                }

                if cwdToProcesses.isEmpty { break }
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
    private func readAndParse(file: URL) -> JSONLParseResult? {
        for size in [2_048, 8_192, 32_768, 65_536] {
            if let content = readTail(of: file, maxBytes: size),
               let result = JSONLParser.parseLastState(from: content) {
                return result
            }
        }
        return nil
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

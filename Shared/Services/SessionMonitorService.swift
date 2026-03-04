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

    private var claudeProjectsDir: URL {
        let home: String
        if let pw = getpwuid(getuid()) {
            home = String(cString: pw.pointee.pw_dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home).appendingPathComponent(".claude/projects")
    }

    init(scanInterval: TimeInterval = 2.0) {
        self.scanInterval = scanInterval
    }

    func startMonitoring() {
        // Cancel any existing timer to prevent double-scheduling
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

    private func scan() {
        // Step 1: Find running claude processes and their cwds
        let processes = ProcessResolver.findClaudeProcesses()
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

        // Step 2: Build a lookup of process cwd → process info
        // Normalize worktree paths: strip .claude/worktrees/<name> suffix
        var cwdToProcess: [String: ClaudeProcessInfo] = [:]
        for proc in processes {
            cwdToProcess[proc.cwd] = proc
            // Also register the canonical project path for worktrees
            if let range = proc.cwd.range(of: "/.claude/worktrees/") {
                let canonical = String(proc.cwd[proc.cwd.startIndex..<range.lowerBound])
                cwdToProcess[canonical] = proc
            }
        }

        // Step 3: For each running process, find the most recent JSONL
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            sessionsSubject.send([])
            return
        }

        var activeSessions: [ClaudeSession] = []

        // Process longer paths first so worktree-specific dirs match before parent project dirs.
        // E.g. -project--claude-worktrees-foo is processed before -project, preventing stale
        // main-project JONLs from stealing worktree processes via the canonical path key.
        let sortedDirs = projectDirs
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent.count > $1.lastPathComponent.count }

        for dir in sortedDirs {

            let jsonlFiles: [URL]
            do {
                jsonlFiles = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
                    .filter { $0.pathExtension == "jsonl" }
            } catch { continue }

            // Sort by modification date (most recent first)
            let sorted = jsonlFiles.sorted { a, b in
                let aDate = (try? fm.attributesOfItem(atPath: a.path)[.modificationDate] as? Date) ?? .distantPast
                let bDate = (try? fm.attributesOfItem(atPath: b.path)[.modificationDate] as? Date) ?? .distantPast
                return aDate > bDate
            }

            for file in sorted {
                guard let result = readAndParse(file: file) else { continue }

                // Check if a claude process is running for this project path
                guard let process = matchProcess(projectPath: result.projectPath, in: cwdToProcess) else { continue }

                let sessionId = file.deletingPathExtension().lastPathComponent
                let modDate = (try? fm.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? Date()
                let startedAt = readFirstTimestamp(of: file) ?? modDate

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
                    lastUpdate: modDate,
                    startedAt: startedAt,
                    processPid: process.pid
                )
                activeSessions.append(session)

                // Remove ALL entries pointing to this process so it can't double-match
                let matchedPid = process.pid
                cwdToProcess = cwdToProcess.filter { $0.value.pid != matchedPid }

                // Continue to find other sessions for different processes
                if cwdToProcess.isEmpty { break }
            }
        }

        activeSessions.sort { $0.startedAt < $1.startedAt }
        sessionsSubject.send(activeSessions)
    }

    /// Match a JSONL project path to a running Claude process.
    /// Exact match first, then worktree-aware match (CWD is inside projectPath/.claude/worktrees/).
    private func matchProcess(projectPath: String, in lookup: [String: ClaudeProcessInfo]) -> ClaudeProcessInfo? {
        // Exact match on project path
        if let proc = lookup[projectPath] { return proc }

        // Worktree match: a process CWD like /project/.claude/worktrees/foo should match /project
        for (cwd, proc) in lookup {
            if cwd.hasPrefix(projectPath + "/.claude/worktrees/") {
                return proc
            }
            // Reverse: projectPath is a worktree path of a process CWD
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

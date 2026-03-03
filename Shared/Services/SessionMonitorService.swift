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
        let fm = FileManager.default
        let projectsDir = claudeProjectsDir

        guard fm.fileExists(atPath: projectsDir.path) else {
            sessionsSubject.send([])
            return
        }

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            sessionsSubject.send([])
            return
        }

        var activeSessions: [ClaudeSession] = []
        let now = Date()
        let deadThreshold: TimeInterval = 60

        for dir in projectDirs {
            guard dir.hasDirectoryPath else { continue }

            let jsonlFiles: [URL]
            do {
                jsonlFiles = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
                    .filter { $0.pathExtension == "jsonl" }
            } catch { continue }

            for file in jsonlFiles {
                guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                      let modDate = attrs[.modificationDate] as? Date else { continue }

                guard now.timeIntervalSince(modDate) < deadThreshold else { continue }

                guard let content = readTail(of: file, maxBytes: 4096),
                      let result = JSONLParser.parseLastState(from: content) else { continue }

                let sessionId = file.deletingPathExtension().lastPathComponent
                let startedAt = readFirstTimestamp(of: file) ?? modDate

                let session = ClaudeSession(
                    id: sessionId,
                    projectPath: result.projectPath,
                    gitBranch: result.gitBranch,
                    model: result.model,
                    state: result.state,
                    lastUpdate: modDate,
                    startedAt: startedAt
                )
                activeSessions.append(session)
            }
        }

        activeSessions.sort { $0.lastUpdate > $1.lastUpdate }
        sessionsSubject.send(activeSessions)
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

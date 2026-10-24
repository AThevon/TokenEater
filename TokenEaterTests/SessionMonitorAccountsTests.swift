import Testing
import Foundation
import Combine

/// Agent Watchers across every tracked Claude config folder: each folder's
/// registry claims its own pids, a session is resolved inside the folder that
/// declared it, and carries that folder's account.
@Suite("Session scan across Claude accounts")
struct SessionMonitorAccountsTests {

    private let work = AccountID(rawValue: "acct-work")

    private func line(sessionId: String, cwd: String) -> String {
        """
        {"type":"assistant","sessionId":"\(sessionId)","cwd":"\(cwd)","gitBranch":"main","timestamp":"2026-09-01T12:00:00.000Z","message":{"role":"assistant","model":"claude-opus-4-7","stop_reason":"end_turn","content":[]}}
        """
    }

    /// One Claude config folder: `projects/` and `sessions/`.
    private struct Folder {
        let root: ClaudeConfigRoot
        let base: URL

        @discardableResult
        func write(transcript sessionId: String, cwd: String, line: String) throws -> URL {
            let dir = root.projectsURL.appendingPathComponent("-" + cwd.replacingOccurrences(of: "/", with: "-"))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(sessionId).jsonl")
            try line.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        func register(pid: Int32, sessionId: String, cwd: String) throws {
            try """
            {"pid":\(pid),"sessionId":"\(sessionId)","cwd":"\(cwd)"}
            """.write(to: root.sessionsURL.appendingPathComponent("\(pid).json"), atomically: true, encoding: .utf8)
        }
    }

    private func makeFolder(_ base: URL, name: String, account: AccountID) throws -> Folder {
        let dir = base.appendingPathComponent(name)
        let root = ClaudeConfigRoot(
            account: account,
            projectsURL: dir.appendingPathComponent("projects"),
            sessionsURL: dir.appendingPathComponent("sessions")
        )
        try FileManager.default.createDirectory(at: root.projectsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.sessionsURL, withIntermediateDirectories: true)
        return Folder(root: root, base: dir)
    }

    private func makeBase() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("te-accounts-scan-\(UUID().uuidString)")
    }

    private func makeService(_ roots: [ClaudeConfigRoot], processes: [ClaudeProcessInfo]) -> SessionMonitorService {
        let service = SessionMonitorService(
            scanInterval: 999,
            projectDirFreshness: 24 * 60 * 60,
            claudeProjectsDirOverride: roots[0].projectsURL,
            claudeSessionsDirOverride: roots[0].sessionsURL,
            processProvider: { processes }
        )
        service.setRoots(roots)
        service.waitForPendingChanges()
        return service
    }

    private func scanOnce(_ service: SessionMonitorService) -> [ClaudeSession] {
        var captured: [ClaudeSession] = []
        let cancellable = service.sessionsPublisher.sink { captured = $0 }
        service.scan()
        cancellable.cancel()
        return captured
    }

    private func process(_ pid: Int32, cwd: String) -> ClaudeProcessInfo {
        ClaudeProcessInfo(pid: pid, parentPid: 1, cwd: cwd, sourceKind: .terminal)
    }

    @Test("each folder's registry claims its own pid, and the session carries that account")
    func pidsFollowTheirFolder() throws {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let main = try makeFolder(base, name: ".claude", account: .main)
        let other = try makeFolder(base, name: ".claude-work", account: work)
        let mainSid = "aaaaaaaa-0000-4000-8000-00000000000a"
        let workSid = "bbbbbbbb-0000-4000-8000-00000000000b"
        try main.write(transcript: mainSid, cwd: "/repo/perso", line: line(sessionId: mainSid, cwd: "/repo/perso"))
        try other.write(transcript: workSid, cwd: "/repo/job", line: line(sessionId: workSid, cwd: "/repo/job"))
        try main.register(pid: 9101, sessionId: mainSid, cwd: "/repo/perso")
        try other.register(pid: 9102, sessionId: workSid, cwd: "/repo/job")

        let service = makeService(
            [main.root, other.root],
            processes: [process(9101, cwd: "/repo/perso"), process(9102, cwd: "/repo/job")]
        )
        let sessions = scanOnce(service)

        #expect(sessions.count == 2)
        #expect(sessions.first { $0.id == mainSid }?.account == .main)
        #expect(sessions.first { $0.id == workSid }?.account == work)
        #expect(sessions.first { $0.id == workSid }?.transcriptPath?.contains("/.claude-work/projects/") == true)
    }

    @Test("a session id present in two folders resolves in the folder whose registry names it")
    func sameSessionIdTakesTheRegistryFolder() throws {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let main = try makeFolder(base, name: ".claude", account: .main)
        let other = try makeFolder(base, name: ".claude-work", account: work)
        let sid = "cccccccc-0000-4000-8000-00000000000c"
        // Same id under both folders; the main copy is the newer one, which
        // a newest-wins rule across folders would wrongly pick.
        let older = try other.write(transcript: sid, cwd: "/repo/shared", line: line(sessionId: sid, cwd: "/repo/shared"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-600)], ofItemAtPath: older.path)
        try main.write(transcript: sid, cwd: "/repo/shared", line: line(sessionId: sid, cwd: "/repo/shared"))
        try other.register(pid: 9201, sessionId: sid, cwd: "/repo/shared")

        let service = makeService([main.root, other.root], processes: [process(9201, cwd: "/repo/shared")])
        let sessions = scanOnce(service)

        #expect(sessions.count == 1)
        #expect(sessions.first?.account == work)
        #expect(sessions.first?.transcriptPath?.contains("/.claude-work/projects/") == true)
    }

    @Test("without a registry entry, the working-directory match runs in every folder")
    func fallbackCoversEveryFolder() throws {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let main = try makeFolder(base, name: ".claude", account: .main)
        let other = try makeFolder(base, name: ".claude-work", account: work)
        let sid = "dddddddd-0000-4000-8000-00000000000d"
        try other.write(transcript: sid, cwd: "/repo/job", line: line(sessionId: sid, cwd: "/repo/job"))

        let service = makeService([main.root, other.root], processes: [process(9301, cwd: "/repo/job")])
        let sessions = scanOnce(service)

        #expect(sessions.map(\.id) == [sid])
        #expect(sessions.first?.account == work)
    }

    @Test("a folder dropped from the roots yields nothing on the next scan")
    func removedRootStopsYielding() throws {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let main = try makeFolder(base, name: ".claude", account: .main)
        let other = try makeFolder(base, name: ".claude-work", account: work)
        let sid = "eeeeeeee-0000-4000-8000-00000000000e"
        try other.write(transcript: sid, cwd: "/repo/job", line: line(sessionId: sid, cwd: "/repo/job"))
        try other.register(pid: 9401, sessionId: sid, cwd: "/repo/job")

        let service = makeService([main.root, other.root], processes: [process(9401, cwd: "/repo/job")])
        #expect(scanOnce(service).first?.account == work)

        service.setRoots([main.root])
        service.waitForPendingChanges()
        #expect(scanOnce(service).isEmpty)
    }

    @Test("a folder that does not exist yet is skipped, not fatal")
    func missingFolderSkipped() throws {
        let base = makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let main = try makeFolder(base, name: ".claude", account: .main)
        let ghost = ClaudeConfigRoot(
            account: work,
            projectsURL: base.appendingPathComponent(".claude-ghost/projects"),
            sessionsURL: base.appendingPathComponent(".claude-ghost/sessions")
        )
        let sid = "ffffffff-0000-4000-8000-00000000000f"
        try main.write(transcript: sid, cwd: "/repo/perso", line: line(sessionId: sid, cwd: "/repo/perso"))
        try main.register(pid: 9501, sessionId: sid, cwd: "/repo/perso")

        let service = makeService([main.root, ghost], processes: [process(9501, cwd: "/repo/perso")])
        #expect(scanOnce(service).first?.account == .main)
    }
}

import Testing
import Foundation
import Combine

/// #255: the scan used to re-enumerate every project dir and re-parse every
/// matched transcript on each tick. The fix caches dir listings (invalidated
/// by dir mtime, which moves on add/remove/rename but not on appends), tail
/// parses (invalidated by file mtime + size), and first-line timestamps
/// (append-only files never change their first line). These tests pin the
/// invalidation behavior across consecutive scans on one service instance.
///
/// Dir mtimes are pinned to PAST values throughout: a just-modified dir is
/// deliberately re-enumerated for 2s regardless of the cache (coarse-mtime
/// volumes), so only a stable past mtime proves the cache comparison itself.
@Suite("Session monitor cross-tick caches invalidate correctly (#255)")
struct SessionMonitorCacheTests {

    private func idleLine(sessionId: String, cwd: String) -> String {
        """
        {"type":"assistant","sessionId":"\(sessionId)","cwd":"\(cwd)","gitBranch":"main","timestamp":"2026-09-01T12:00:00.000Z","message":{"role":"assistant","model":"claude-opus-4-7","stop_reason":"end_turn","content":[]}}
        """
    }

    private func thinkingLine(sessionId: String, cwd: String) -> String {
        """
        {"type":"assistant","sessionId":"\(sessionId)","cwd":"\(cwd)","gitBranch":"main","timestamp":"2026-09-01T12:00:05.000Z","message":{"role":"assistant","model":"claude-opus-4-7","stop_reason":null,"content":[]}}
        """
    }

    private struct Env {
        let root: URL
        let projectsDir: URL
        let sessionsDir: URL
        let projectDir: URL
        let cwd: String
        let sessionId: String

        var transcript: URL { projectDir.appendingPathComponent("\(sessionId).jsonl") }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    private func makeEnv() throws -> Env {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("te-cache-\(UUID().uuidString)")
        let projectsDir = root.appendingPathComponent("projects")
        let sessionsDir = root.appendingPathComponent("sessions")
        let projectDir = projectsDir.appendingPathComponent("-checkout-x")
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let env = Env(
            root: root,
            projectsDir: projectsDir,
            sessionsDir: sessionsDir,
            projectDir: projectDir,
            cwd: root.appendingPathComponent("checkout-x").path,
            sessionId: "cccccccc-0000-4000-8000-000000000003"
        )
        try idleLine(sessionId: env.sessionId, cwd: env.cwd)
            .write(to: env.transcript, atomically: true, encoding: .utf8)
        return env
    }

    private func makeService(_ env: Env, pid: Int32) -> SessionMonitorService {
        let process = ClaudeProcessInfo(pid: pid, parentPid: 1, cwd: env.cwd, sourceKind: .terminal)
        return SessionMonitorService(
            scanInterval: 999,
            projectDirFreshness: 24 * 60 * 60,
            claudeProjectsDirOverride: env.projectsDir,
            claudeSessionsDirOverride: env.sessionsDir,
            processProvider: { [process] }
        )
    }

    private func scanOnce(_ service: SessionMonitorService) -> [ClaudeSession] {
        var captured: [ClaudeSession] = []
        let cancellable = service.sessionsPublisher.sink { captured = $0 }
        service.scan()
        cancellable.cancel()
        return captured
    }

    private func setMtime(_ date: Date, at url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func writeRegistry(_ env: Env, pid: Int32, sessionId: String) throws {
        try """
        {"pid":\(pid),"sessionId":"\(sessionId)","cwd":"\(env.cwd)"}
        """.write(to: env.sessionsDir.appendingPathComponent("\(pid).json"),
                  atomically: true, encoding: .utf8)
    }

    private func append(_ line: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        handle.write(Data(("\n" + line).utf8))
        try handle.close()
    }

    @Test("an append is re-parsed even though the dir listing stays cached (fallback pass)")
    func appendReparsedDespiteCachedDirListing() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        // A stable, past dir mtime: the cached listing stays valid across both
        // scans, so only the file's own stamp can carry the invalidation,
        // which is exactly the append case (appends never touch dir mtime).
        let dirMtime = Date().addingTimeInterval(-3600)
        try setMtime(dirMtime, at: env.projectDir)
        let service = makeService(env, pid: 8000)

        let first = scanOnce(service)
        #expect(first.first?.state == .idle)

        try append(thinkingLine(sessionId: env.sessionId, cwd: env.cwd), to: env.transcript)
        try setMtime(Date().addingTimeInterval(5), at: env.transcript)
        try setMtime(dirMtime, at: env.projectDir)

        let second = scanOnce(service)
        #expect(second.first?.state == .thinking)
    }

    @Test("an append is re-parsed on the registry pass too")
    func appendReparsedOnRegistryPass() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let dirMtime = Date().addingTimeInterval(-3600)
        try setMtime(dirMtime, at: env.projectDir)
        try writeRegistry(env, pid: 8005, sessionId: env.sessionId)
        let service = makeService(env, pid: 8005)

        let first = scanOnce(service)
        #expect(first.first?.state == .idle)
        #expect(first.first?.processPid == 8005)

        try append(thinkingLine(sessionId: env.sessionId, cwd: env.cwd), to: env.transcript)
        try setMtime(Date().addingTimeInterval(5), at: env.transcript)
        try setMtime(dirMtime, at: env.projectDir)

        let second = scanOnce(service)
        #expect(second.first?.state == .thinking)
    }

    @Test("a transcript added to an already-cached dir is picked up (mtime-bump invalidation)")
    func newTranscriptInCachedDirInvalidatesListing() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        try setMtime(Date().addingTimeInterval(-3600), at: env.projectDir)
        let service = makeService(env, pid: 8004)

        let first = scanOnce(service)
        #expect(first.first?.id == env.sessionId)

        // A new session starts in the SAME dir, whose listing was cached by
        // the first scan. Creating the file bumps the dir mtime; re-pin it to
        // a distinct PAST value so only the mtime comparison itself, not the
        // hot-dir re-enumeration window, can refresh the listing.
        let newSid = "ffffffff-0000-4000-8000-000000000006"
        try idleLine(sessionId: newSid, cwd: env.cwd)
            .write(to: env.projectDir.appendingPathComponent("\(newSid).jsonl"), atomically: true, encoding: .utf8)
        try setMtime(Date().addingTimeInterval(-1800), at: env.projectDir)
        try writeRegistry(env, pid: 8004, sessionId: newSid)

        let second = scanOnce(service)
        #expect(second.first?.id == newSid)
        #expect(second.first?.transcriptPath?.hasSuffix("-checkout-x/\(newSid).jsonl") == true)
    }

    @Test("a transcript in a new project dir is picked up (listing cache miss)")
    func newTranscriptInNewDirIsPickedUp() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let service = makeService(env, pid: 8001)
        _ = scanOnce(service)

        // A second session appears in a NEW project dir after the first scan,
        // and the registry binds the process to it (#233 resolution path).
        let newSid = "dddddddd-0000-4000-8000-000000000004"
        let otherDir = env.projectsDir.appendingPathComponent("-checkout-y")
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        let otherCwd = env.root.appendingPathComponent("checkout-y").path
        try idleLine(sessionId: newSid, cwd: otherCwd)
            .write(to: otherDir.appendingPathComponent("\(newSid).jsonl"), atomically: true, encoding: .utf8)
        try writeRegistry(env, pid: 8001, sessionId: newSid)

        let second = scanOnce(service)
        #expect(second.count == 1)
        #expect(second.first?.id == newSid)
        #expect(second.first?.transcriptPath?.hasSuffix("-checkout-y/\(newSid).jsonl") == true)
    }

    @Test("a deleted transcript drops its session on the next tick")
    func deletedTranscriptDropsSession() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let service = makeService(env, pid: 8002)

        let first = scanOnce(service)
        #expect(first.count == 1)

        try FileManager.default.removeItem(at: env.transcript)

        let second = scanOnce(service)
        #expect(second.isEmpty)
    }

    @Test("a stale transcript is never bound to a second process (per-file freshness gate)")
    func staleTranscriptNotBoundToSecondProcess() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        // A second, STALE transcript in the same project dir (backdated past
        // the freshness window), plus a second cwd-matched process with no
        // registry entry, like a short-lived helper spawn from the VSCode
        // extension (#260): the helper must not resurrect the stale session
        // as a ghost watcher.
        let staleSid = "abababab-0000-4000-8000-000000000007"
        let staleFile = env.projectDir.appendingPathComponent("\(staleSid).jsonl")
        try idleLine(sessionId: staleSid, cwd: env.cwd)
            .write(to: staleFile, atomically: true, encoding: .utf8)
        try setMtime(Date().addingTimeInterval(-2 * 3600), at: staleFile)

        let p1 = ClaudeProcessInfo(pid: 8100, parentPid: 1, cwd: env.cwd, sourceKind: .terminal)
        let p2 = ClaudeProcessInfo(pid: 8101, parentPid: 1, cwd: env.cwd, sourceKind: .terminal)
        let service = SessionMonitorService(
            scanInterval: 999,
            projectDirFreshness: 30 * 60,
            claudeProjectsDirOverride: env.projectsDir,
            claudeSessionsDirOverride: env.sessionsDir,
            processProvider: { [p1, p2] }
        )

        let sessions = scanOnce(service)
        #expect(sessions.map(\.id) == [env.sessionId])
    }

    @Test("a registry entry written after the first scan is honored (#233)")
    func lateRegistryEntryHonored() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        // A second project dir holds a resumed session's transcript, present
        // from the start; the process itself runs from checkout-x's cwd.
        let resumedSid = "eeeeeeee-0000-4000-8000-000000000005"
        let otherDir = env.projectsDir.appendingPathComponent("-checkout-z")
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        let otherCwd = env.root.appendingPathComponent("checkout-z").path
        try idleLine(sessionId: resumedSid, cwd: otherCwd)
            .write(to: otherDir.appendingPathComponent("\(resumedSid).jsonl"), atomically: true, encoding: .utf8)

        let service = makeService(env, pid: 8003)

        // First scan: no registry, the cwd heuristic binds to checkout-x.
        let first = scanOnce(service)
        #expect(first.first?.id == env.sessionId)

        // Claude Code then writes its registry entry pointing at the resumed
        // session; the next tick must re-resolve against it, not against
        // anything cached on the first tick.
        try writeRegistry(env, pid: 8003, sessionId: resumedSid)

        let second = scanOnce(service)
        #expect(second.first?.id == resumedSid)
        #expect(second.first?.transcriptPath?.hasSuffix("-checkout-z/\(resumedSid).jsonl") == true)
    }
}

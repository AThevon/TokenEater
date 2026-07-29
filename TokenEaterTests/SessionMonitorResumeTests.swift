import Testing
import Foundation

/// #233: a session opened with `claude --resume` is rendered from the wrong
/// transcript. The resumed session's transcript lives under its original
/// project dir, but the process was launched from a different directory, so
/// the old working-directory match bound the process to whatever session
/// lived in the launch dir (typically an older, idle one) instead of the
/// session the process is actually running. The registry (`<pid>.json`) knows
/// the exact sessionId, so the scan now uses it.
@Suite("Session matching resolves the resumed session, not the launch dir")
struct SessionMonitorResumeTests {

    private func jsonlLine(sessionId: String, cwd: String) -> String {
        """
        {"type":"user","sessionId":"\(sessionId)","cwd":"\(cwd)","gitBranch":"main","timestamp":"2026-07-07T12:00:00.000Z","message":{"role":"user","content":"hi"}}
        """
    }

    private struct Env {
        let projectsDir: URL
        let sessionsDir: URL
        let pathA: String   // launch cwd (holds the older idle session A)
        let pathB: String   // the resumed session B's original project
        let sessionA: String
        let sessionB: String

        func cleanup() {
            try? FileManager.default.removeItem(at: projectsDir.deletingLastPathComponent())
        }
    }

    /// Two project dirs, one transcript each: A under the launch cwd, B under a
    /// different project. Optionally writes a registry entry for the process.
    private func makeEnv() throws -> Env {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("te-resume-\(UUID().uuidString)")
        let projectsDir = root.appendingPathComponent("projects")
        let sessionsDir = root.appendingPathComponent("sessions")
        try fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let pathA = root.appendingPathComponent("checkout-a").path
        let pathB = root.appendingPathComponent("checkout-b").path
        let sessionA = "aaaaaaaa-0000-4000-8000-000000000001"
        let sessionB = "bbbbbbbb-0000-4000-8000-000000000002"

        let dirA = projectsDir.appendingPathComponent("-checkout-a")
        let dirB = projectsDir.appendingPathComponent("-checkout-b")
        try fm.createDirectory(at: dirA, withIntermediateDirectories: true)
        try fm.createDirectory(at: dirB, withIntermediateDirectories: true)

        try jsonlLine(sessionId: sessionA, cwd: pathA)
            .write(to: dirA.appendingPathComponent("\(sessionA).jsonl"), atomically: true, encoding: .utf8)
        try jsonlLine(sessionId: sessionB, cwd: pathB)
            .write(to: dirB.appendingPathComponent("\(sessionB).jsonl"), atomically: true, encoding: .utf8)

        return Env(projectsDir: projectsDir, sessionsDir: sessionsDir,
                   pathA: pathA, pathB: pathB, sessionA: sessionA, sessionB: sessionB)
    }

    private func writeRegistry(_ env: Env, pid: Int32, sessionId: String, name: String?) throws {
        let nameField = name.map { ",\"name\":\"\($0)\",\"nameSource\":\"user\"" } ?? ""
        let entry = """
        {"pid":\(pid),"sessionId":"\(sessionId)","cwd":"\(env.pathA)"\(nameField)}
        """
        try entry.write(to: env.sessionsDir.appendingPathComponent("\(pid).json"),
                        atomically: true, encoding: .utf8)
    }

    private func makeService(_ env: Env, cwd: String, pid: Int32) -> SessionMonitorService {
        let process = ClaudeProcessInfo(pid: pid, parentPid: 1, cwd: cwd, sourceKind: .terminal)
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

    @Test("the registry sessionId wins over the launch-directory match")
    func resumedSessionResolvesToItsOwnTranscript() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        // Process launched in checkout-a, but the registry says it is running
        // the resumed session B (whose transcript lives under checkout-b).
        try writeRegistry(env, pid: 7000, sessionId: env.sessionB, name: "resumed work")

        let sessions = scanOnce(makeService(env, cwd: env.pathA, pid: 7000))

        #expect(sessions.count == 1)
        #expect(sessions.first?.id == env.sessionB)
        #expect(sessions.first?.projectPath == env.pathB)
        #expect(sessions.first?.userSessionName == "resumed work")
    }

    @Test("without a registry entry it falls back to the working-directory match")
    func noRegistryFallsBackToCwdMatch() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        // No `<pid>.json` written -> old heuristic: cwd checkout-a binds to A.

        let sessions = scanOnce(makeService(env, cwd: env.pathA, pid: 7001))

        #expect(sessions.count == 1)
        #expect(sessions.first?.id == env.sessionA)
        #expect(sessions.first?.projectPath == env.pathA)
    }

    @Test("a stale registry sessionId that no longer exists falls back to cwd")
    func staleRegistrySessionIdFallsBack() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        // Registry points at a session whose transcript is gone -> fall back.
        try writeRegistry(env, pid: 7002, sessionId: "deadbeef-0000-4000-8000-000000000000", name: "gone")

        let sessions = scanOnce(makeService(env, cwd: env.pathA, pid: 7002))

        #expect(sessions.count == 1)
        #expect(sessions.first?.id == env.sessionA)
        #expect(sessions.first?.userSessionName == nil)
    }
}

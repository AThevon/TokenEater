import Testing
import Foundation
import Combine

@Suite("Session name resolution from the Claude Code session registry")
struct SessionMonitorNameTests {

    // MARK: - Fixtures

    private static let sessionId = "aab8ad29-0efe-4450-a838-8478e89bfec2"
    private static let pid: Int32 = 4242

    /// One valid JSONL user event - enough for JSONLParser to yield meta + state.
    private func jsonlLine(sessionId: String, cwd: String) -> String {
        """
        {"type":"user","sessionId":"\(sessionId)","cwd":"\(cwd)","gitBranch":"main","timestamp":"2026-07-07T12:00:00.000Z","message":{"role":"user","content":"hi"}}
        """
    }

    private struct Env {
        let projectsDir: URL
        let sessionsDir: URL
        let projectPath: String

        func cleanup() {
            try? FileManager.default.removeItem(at: projectsDir)
            try? FileManager.default.removeItem(at: sessionsDir)
        }
    }

    /// Build a projects tree with a single parseable session JSONL plus an
    /// empty sessions registry dir, both under unique temp roots.
    private func makeEnv() throws -> Env {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("te-name-\(UUID().uuidString)")
        let projectsDir = root.appendingPathComponent("projects")
        let sessionsDir = root.appendingPathComponent("sessions")
        let projectPath = root.appendingPathComponent("checkout").path

        let projectDir = projectsDir.appendingPathComponent("-fake-project")
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let jsonl = projectDir.appendingPathComponent("\(Self.sessionId).jsonl")
        try jsonlLine(sessionId: Self.sessionId, cwd: projectPath)
            .write(to: jsonl, atomically: true, encoding: .utf8)

        return Env(projectsDir: projectsDir, sessionsDir: sessionsDir, projectPath: projectPath)
    }

    private func writeRegistry(
        _ env: Env,
        pid: Int32 = SessionMonitorNameTests.pid,
        sessionId: String = SessionMonitorNameTests.sessionId,
        name: String,
        nameSource: String?
    ) throws {
        let sourceField = nameSource.map { ",\"nameSource\":\"\($0)\"" } ?? ""
        let entry = """
        {"pid":\(pid),"sessionId":"\(sessionId)","cwd":"\(env.projectPath)","name":"\(name)"\(sourceField)}
        """
        try entry.write(
            to: env.sessionsDir.appendingPathComponent("\(pid).json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func makeService(_ env: Env) -> SessionMonitorService {
        let process = ClaudeProcessInfo(
            pid: Self.pid,
            parentPid: 1,
            cwd: env.projectPath,
            sourceKind: .terminal
        )
        return SessionMonitorService(
            scanInterval: 999,
            projectDirFreshness: 24 * 60 * 60,
            claudeProjectsDirOverride: env.projectsDir,
            claudeSessionsDirOverride: env.sessionsDir,
            processProvider: { [process] }
        )
    }

    /// Run one synchronous scan and capture the emitted sessions.
    private func scanOnce(_ service: SessionMonitorService) -> [ClaudeSession] {
        var captured: [ClaudeSession] = []
        let cancellable = service.sessionsPublisher.sink { captured = $0 }
        service.scan()
        cancellable.cancel()
        return captured
    }

    // MARK: - Model

    @Test("displayName prefers the user-set session name over branch and project")
    func displayNamePrefersUserName() {
        var session = ClaudeSession(
            id: "abc",
            projectPath: "/Users/dev/my-project",
            gitBranch: "feature/thing",
            model: nil,
            state: .idle,
            lastUpdate: Date(),
            startedAt: Date(),
            processPid: 1
        )
        #expect(session.displayName == "feature/thing")

        session.userSessionName = "payment refactor"
        #expect(session.displayName == "payment refactor")
    }

    // MARK: - Registry reads during scan

    @Test("scan picks up a user-set name from the session registry")
    func scanPicksUpUserName() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        try writeRegistry(env, name: "payment refactor", nameSource: "user")

        let sessions = scanOnce(makeService(env))

        #expect(sessions.count == 1)
        #expect(sessions.first?.userSessionName == "payment refactor")
    }

    @Test("a rename that omits nameSource is treated as user-set")
    func missingNameSourceTreatedAsUserSet() throws {
        // Observed on-disk behavior of Claude Code 2.1.202: after a live
        // /rename the registry entry keeps `name` but drops the `nameSource`
        // field entirely - it does NOT write `nameSource: "user"`.
        let env = try makeEnv()
        defer { env.cleanup() }
        try writeRegistry(env, name: "tokeneater-monitor-name", nameSource: nil)

        let sessions = scanOnce(makeService(env))

        #expect(sessions.count == 1)
        #expect(sessions.first?.userSessionName == "tokeneater-monitor-name")
    }

    @Test("derived (auto-generated) names are ignored")
    func derivedNamesIgnored() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        try writeRegistry(env, name: "tokeneater-01", nameSource: "derived")

        let sessions = scanOnce(makeService(env))

        #expect(sessions.count == 1)
        #expect(sessions.first?.userSessionName == nil)
    }

    @Test("a stale registry file whose sessionId does not match is ignored")
    func staleRegistryFileIgnored() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        // Same pid on disk, but the file belongs to an older session (pid reuse).
        try writeRegistry(
            env,
            sessionId: "00000000-dead-beef-0000-000000000000",
            name: "old session",
            nameSource: "user"
        )

        let sessions = scanOnce(makeService(env))

        #expect(sessions.count == 1)
        #expect(sessions.first?.userSessionName == nil)
    }

    @Test("a missing registry file leaves the name nil")
    func missingRegistryFile() throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let sessions = scanOnce(makeService(env))

        #expect(sessions.count == 1)
        #expect(sessions.first?.userSessionName == nil)
    }

    @Test("a mid-session rename is picked up on the next scan")
    func renamePickedUpOnNextScan() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let service = makeService(env)

        try writeRegistry(env, name: "first name", nameSource: "user")
        #expect(scanOnce(service).first?.userSessionName == "first name")

        try writeRegistry(env, name: "second name", nameSource: "user")
        #expect(scanOnce(service).first?.userSessionName == "second name")
    }

    @Test("an empty name is treated as unset")
    func emptyNameIgnored() throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        try writeRegistry(env, name: "", nameSource: "user")

        let sessions = scanOnce(makeService(env))

        #expect(sessions.count == 1)
        #expect(sessions.first?.userSessionName == nil)
    }
}

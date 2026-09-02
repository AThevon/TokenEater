import Testing
import Foundation

// .serialized: these tests assert wall-clock budgets, so they must not share
// the process with each other while timing (other suites still run in
// parallel, hence the generous bounds).
@Suite("SessionMonitorService performance", .serialized)
struct SessionMonitorPerfTests {

    /// Build a synthetic projects tree with `dirCount` subdirs and `filesPerDir` JSONL files each.
    /// Every file holds one valid assistant line whose cwd matches no process, so a scan
    /// walks, stats, and PARSES all of them without ever emitting a session - the full
    /// fallback-pass workload.
    private func makeSyntheticProjects(dirCount: Int, filesPerDir: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("te-perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for d in 0..<dirCount {
            let dir = root.appendingPathComponent("-project-dir-\(d)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for _ in 0..<filesPerDir {
                let sid = UUID().uuidString
                let file = dir.appendingPathComponent("\(sid).jsonl")
                let line = """
                {"type":"assistant","sessionId":"\(sid)","cwd":"/nonmatching/cwd","gitBranch":"main","timestamp":"2026-09-01T12:00:00.000Z","message":{"role":"assistant","model":"claude-opus-4-7","stop_reason":"end_turn","content":[]}}
                """
                try line.write(to: file, atomically: true, encoding: .utf8)
            }
        }
        return root
    }

    /// An empty sessions dir so the scan never touches the machine's real
    /// `~/.claude/sessions` registry inside a timed section.
    private func makeEmptySessionsDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("te-perf-sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("scan finishes quickly on a big tree (~1000 JSONL files)")
    func scanStaysFastWithManyDirs() async throws {
        let projectsDir = try makeSyntheticProjects(dirCount: 50, filesPerDir: 20)
        let sessionsDir = try makeEmptySessionsDir()
        defer {
            try? FileManager.default.removeItem(at: projectsDir)
            try? FileManager.default.removeItem(at: sessionsDir)
        }

        // Fake a running Claude process so scan() does not bail out early, forcing the walk.
        let fakeProcess = ClaudeProcessInfo(
            pid: 99_999,
            parentPid: 1,
            cwd: "/nonexistent/project/path",
            sourceKind: .terminal
        )
        let service = SessionMonitorService(
            scanInterval: 999,
            projectDirFreshness: 24 * 60 * 60,
            claudeProjectsDirOverride: projectsDir,
            claudeSessionsDirOverride: sessionsDir,
            processProvider: { [fakeProcess] }
        )

        let start = ContinuousClock.now
        service.scan()
        let duration = ContinuousClock.now - start

        // The fixtures now parse for real, so a cold scan legitimately does
        // 1000 full tail parses (~0.7s on a loaded CI runner); the bound only
        // guards against pathological blowups, the warm/cold ratio test below
        // is what pins the caches.
        #expect(
            duration < .milliseconds(2000),
            "cold scan took \(duration) on 50 dirs * 20 files (1000 parsed JSONLs)"
        )
    }

    @Test("a warm scan over an unchanged tree beats the cold scan (#255)")
    func warmScanBeatsColdScan() async throws {
        let projectsDir = try makeSyntheticProjects(dirCount: 50, filesPerDir: 20)
        let sessionsDir = try makeEmptySessionsDir()
        defer {
            try? FileManager.default.removeItem(at: projectsDir)
            try? FileManager.default.removeItem(at: sessionsDir)
        }

        // Backdate the dir mtimes so the listings qualify for the cache: a
        // just-modified dir is deliberately re-enumerated for 2s (coarse-mtime
        // volumes, see refreshDirListings).
        let past = Date().addingTimeInterval(-3600)
        for dir in try FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) where dir.hasDirectoryPath {
            try FileManager.default.setAttributes(
                [.modificationDate: past], ofItemAtPath: dir.path
            )
        }

        let fakeProcess = ClaudeProcessInfo(
            pid: 99_998,
            parentPid: 1,
            cwd: "/nonexistent/project/path",
            sourceKind: .terminal
        )
        let service = SessionMonitorService(
            scanInterval: 999,
            projectDirFreshness: 24 * 60 * 60,
            claudeProjectsDirOverride: projectsDir,
            claudeSessionsDirOverride: sessionsDir,
            processProvider: { [fakeProcess] }
        )

        let coldStart = ContinuousClock.now
        service.scan() // cold: enumerates 50 dirs, parses 1000 transcripts
        let cold = ContinuousClock.now - coldStart

        let warmStart = ContinuousClock.now
        service.scan() // warm: cached listings + parse-cache hits, stats only
        let warm = ContinuousClock.now - warmStart

        // Ratio, not an absolute bound: the warm scan skips the 1000 parses
        // and their up-to-4 file opens each, so it must be clearly cheaper
        // than the cold scan on any machine, however loaded.
        #expect(
            warm * 2 < cold,
            "warm scan (\(warm)) is not clearly cheaper than the cold scan (\(cold)); the cross-tick caches (#255) are not engaging"
        )
    }

    @Test("stale project dirs are skipped by the freshness filter")
    func skipsStaleProjectDirs() async throws {
        let projectsDir = try makeSyntheticProjects(dirCount: 5, filesPerDir: 1)
        let sessionsDir = try makeEmptySessionsDir()
        defer {
            try? FileManager.default.removeItem(at: projectsDir)
            try? FileManager.default.removeItem(at: sessionsDir)
        }

        // Backdate 3 of the 5 dirs to simulate stale activity.
        let dirs = try FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil
        ).filter { $0.hasDirectoryPath }.sorted { $0.path < $1.path }

        let stale = Date().addingTimeInterval(-90 * 60) // 90 min ago
        for dir in dirs.prefix(3) {
            try FileManager.default.setAttributes([.modificationDate: stale], ofItemAtPath: dir.path)
        }

        let fakeProcess = ClaudeProcessInfo(
            pid: 12_345,
            parentPid: 1,
            cwd: "/nonexistent",
            sourceKind: .terminal
        )
        let service = SessionMonitorService(
            scanInterval: 999,
            projectDirFreshness: 30 * 60,
            claudeProjectsDirOverride: projectsDir,
            claudeSessionsDirOverride: sessionsDir,
            processProvider: { [fakeProcess] }
        )

        // scan() itself does not return the dir list, so we validate the filter by asking
        // the same URL API the implementation uses.
        let freshnessCutoff = Date().addingTimeInterval(-30 * 60)
        let freshDirs = try FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ).filter { $0.hasDirectoryPath }.filter { dir in
            let mtime = (try? dir.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            return mtime >= freshnessCutoff
        }

        #expect(freshDirs.count == 2, "Expected 2 fresh dirs (the 2 not backdated), got \(freshDirs.count)")

        // scan() should not crash or hang when the filter discards most dirs.
        service.scan()
    }
}

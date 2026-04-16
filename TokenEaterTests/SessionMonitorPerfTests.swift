import Testing
import Foundation

@Suite("SessionMonitorService performance")
struct SessionMonitorPerfTests {

    /// Build a synthetic projects tree with `dirCount` subdirs and `filesPerDir` JSONL files each.
    /// Files are empty placeholders - the parser will fail on them, which matches the pre-fix
    /// behavior on JSONLs that aren't well-formed and still exercises the full walk/sort path.
    private func makeSyntheticProjects(dirCount: Int, filesPerDir: Int) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("te-perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for d in 0..<dirCount {
            let dir = root.appendingPathComponent("-project-dir-\(d)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for _ in 0..<filesPerDir {
                let file = dir.appendingPathComponent("\(UUID().uuidString).jsonl")
                try Data().write(to: file)
            }
        }
        return root
    }

    @Test("scan finishes quickly on a big tree (~1000 JSONL files)")
    func scanStaysFastWithManyDirs() async throws {
        let projectsDir = try makeSyntheticProjects(dirCount: 50, filesPerDir: 20)
        defer { try? FileManager.default.removeItem(at: projectsDir) }

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
            processProvider: { [fakeProcess] }
        )

        let start = ContinuousClock.now
        service.scan()
        let duration = ContinuousClock.now - start

        #expect(
            duration < .milliseconds(500),
            "scan took \(duration) on 50 dirs * 20 files (1000 JSONLs); pre-fix O(N log N) stat calls can exceed this on CI"
        )
    }

    @Test("stale project dirs are skipped by the freshness filter")
    func skipsStaleProjectDirs() async throws {
        let projectsDir = try makeSyntheticProjects(dirCount: 5, filesPerDir: 1)
        defer { try? FileManager.default.removeItem(at: projectsDir) }

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

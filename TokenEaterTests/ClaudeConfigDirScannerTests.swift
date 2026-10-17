import Testing
import Foundation

@Suite("ClaudeConfigDirScanner")
struct ClaudeConfigDirScannerTests {

    /// Records the Keychain lookups a scan makes.
    private final class Probes: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        func record(_ service: String) { lock.lock(); stored.append(service); lock.unlock() }
        var services: [String] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    /// A throwaway home with the given folders, each holding the given files
    /// (a trailing "/" makes a folder).
    private func makeHome(_ layout: [String: [String]]) throws -> String {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerTests-\(UUID().uuidString)").path
        let fm = FileManager.default
        try fm.createDirectory(atPath: home, withIntermediateDirectories: true)
        for (folder, entries) in layout {
            let dir = home + "/" + folder
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for entry in entries {
                if entry.hasSuffix("/") {
                    try fm.createDirectory(atPath: dir + "/" + entry, withIntermediateDirectories: true)
                } else {
                    fm.createFile(atPath: dir + "/" + entry, contents: Data("{}".utf8))
                }
            }
        }
        return home
    }

    private func path(_ home: String, _ folder: String) -> String {
        ClaudeConfigDirResolver.normalize(home + "/" + folder, home: home)
    }

    @Test("a folder with none of Claude Code's files is ignored, one with projects/ is kept")
    func markers() throws {
        let home = try makeHome([
            ".claude-empty": ["notes.txt"],
            ".claude-work": ["projects/"],
            ".config": ["projects/"],
        ])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let scanner = ClaudeConfigDirScanner(home: home, hasKeychainItem: { _ in false })
        let found = scanner.candidates(excluding: [])
        #expect(found.map(\.path) == [path(home, ".claude-work")])
        #expect(found.first?.displayPath == "~/.claude-work")
        #expect(found.first?.hasLogin == false)
    }

    @Test("a plain file named like a config folder is not a candidate")
    func filesAreNotFolders() throws {
        let home = try makeHome([:])
        defer { try? FileManager.default.removeItem(atPath: home) }
        FileManager.default.createFile(atPath: home + "/.claude-notes", contents: Data())
        let scanner = ClaudeConfigDirScanner(home: home, hasKeychainItem: { _ in true })
        #expect(scanner.candidates(excluding: []).isEmpty)
    }

    @Test("the matched service is the first spelling that has a Keychain item")
    func secondVariantMatches() throws {
        let home = try makeHome([".claude-work": [".claude.json"]])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let candidates = ClaudeConfigDirResolver.serviceCandidates(for: path(home, ".claude-work"), home: home)
        let wanted = candidates[1]
        let scanner = ClaudeConfigDirScanner(home: home, hasKeychainItem: { $0 == wanted })
        let found = try #require(scanner.candidates(excluding: []).first)
        #expect(found.matchedService == wanted)
        #expect(found.hasLogin)
    }

    @Test("a .credentials.json alone counts as a login")
    func credentialsFileIsALogin() throws {
        let home = try makeHome([".claude-side": [".credentials.json"]])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let scanner = ClaudeConfigDirScanner(home: home, hasKeychainItem: { _ in false })
        let found = try #require(scanner.candidates(excluding: []).first)
        #expect(found.matchedService == nil)
        #expect(found.hasCredentialsFile)
        #expect(found.hasLogin)
    }

    @Test("folders already tracked are left out, the default one included")
    func excludesTracked() throws {
        let home = try makeHome([
            ".claude": ["projects/"],
            ".claude-work": ["projects/"],
            ".claude-perso": ["projects/"],
        ])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let scanner = ClaudeConfigDirScanner(home: home, hasKeychainItem: { _ in false })
        let found = scanner.candidates(excluding: [home + "/.claude", "~/.claude-work/"])
        #expect(found.map(\.path) == [path(home, ".claude-perso")])
    }

    @Test("the default folder is offered once the main account moved away from it")
    func offersDefaultFolder() throws {
        let home = try makeHome([".claude": ["projects/"]])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let probed = Probes()
        let scanner = ClaudeConfigDirScanner(home: home, hasKeychainItem: { service in
            probed.record(service)
            return service == ClaudeConfigDirResolver.baseService
        })
        let found = try #require(scanner.candidates(excluding: [home + "/.claude-perso"]).first)
        #expect(found.matchedService == ClaudeConfigDirResolver.baseService)
        #expect(probed.services == [ClaudeConfigDirResolver.baseService])
    }

    @Test("the most recently used folder comes first")
    func ordersByActivity() throws {
        let home = try makeHome([
            ".claude-old": ["projects/"],
            ".claude-new": ["projects/"],
            ".claude-none": [".claude.json"],
        ])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let fm = FileManager.default
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -86_400 * 3)],
                             ofItemAtPath: home + "/.claude-old/projects")
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)],
                             ofItemAtPath: home + "/.claude-new/projects")
        let scanner = ClaudeConfigDirScanner(home: home, hasKeychainItem: { _ in false })
        #expect(scanner.candidates(excluding: []).map(\.path) == [
            path(home, ".claude-new"), path(home, ".claude-old"), path(home, ".claude-none"),
        ])
    }

    @Test("inspect works on any folder, and says when it does not exist")
    func inspectAnyFolder() throws {
        let home = try makeHome(["work/claude": [".credentials.json"]])
        defer { try? FileManager.default.removeItem(atPath: home) }
        let probes = Probes()
        let scanner = ClaudeConfigDirScanner(home: home, hasKeychainItem: { service in
            probes.record(service)
            return false
        })
        let picked = scanner.inspect(path: home + "/work/claude/")
        #expect(picked.path == path(home, "work/claude"))
        #expect(picked.displayPath == "~/work/claude")
        #expect(picked.exists)
        #expect(picked.hasLogin)

        let missing = scanner.inspect(path: home + "/gone")
        #expect(!missing.exists)
        #expect(!missing.hasLogin)
        // A missing folder is never looked up in the Keychain.
        #expect(probes.services.count == ClaudeConfigDirResolver.serviceCandidates(for: picked.path, home: home).count)
    }
}

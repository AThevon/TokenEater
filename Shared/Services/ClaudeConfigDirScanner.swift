import Foundation

/// Looks for Claude Code config folders in the home directory.
///
/// Claude Code keeps one login per config folder: `~/.claude` by default,
/// whatever `CLAUDE_CONFIG_DIR` points at otherwise. People who run several
/// accounts conventionally name those folders `~/.claude-<something>`, so the
/// scan lists the home entries with that shape that hold something Claude
/// Code writes (`projects/`, `.claude.json`, `.credentials.json`).
///
/// It reads no credential. A folder's Keychain item is looked up by the exact
/// service names Claude Code derives from its path, asking for the item's
/// attributes only, which raises no prompt and runs no `security` process.
/// There is no enumeration of the Keychain by prefix either: an item whose
/// folder cannot be named is not offered, and "Choose a folder" covers the
/// rest.
final class ClaudeConfigDirScanner: ClaudeConfigDirScannerProtocol, @unchecked Sendable {
    typealias KeychainProbe = @Sendable (String) -> Bool

    private let home: String
    private let hasKeychainItem: KeychainProbe

    init(
        home: String = ClaudeConfigDirResolver.realHome(),
        hasKeychainItem: @escaping KeychainProbe = { SecurityCLIReader(service: $0).hasCredentialItem() }
    ) {
        self.home = home
        self.hasKeychainItem = hasKeychainItem
    }

    /// The files whose presence makes a folder a Claude Code config folder.
    static let markers = ["projects", ".claude.json", ".credentials.json"]

    func candidates(excluding trackedPaths: Set<String>) -> [ConfigDirCandidate] {
        let fm = FileManager.default
        let excluded = Set(trackedPaths.map { ClaudeConfigDirResolver.normalize($0, home: home) })
        guard let entries = try? fm.contentsOfDirectory(atPath: home) else { return [] }

        let found = entries
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .map { ClaudeConfigDirResolver.normalize(home + "/" + $0, home: home) }
            .filter { path in
                guard !excluded.contains(path), isDirectory(path) else { return false }
                return Self.markers.contains { fm.fileExists(atPath: path + "/" + $0) }
            }
            .map(inspect(path:))

        return found.sorted { lhs, rhs in
            switch (lhs.lastActivity, rhs.lastActivity) {
            case let (l?, r?) where l != r: return l > r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.path < rhs.path
            }
        }
    }

    func inspect(path: String) -> ConfigDirCandidate {
        let fm = FileManager.default
        let normalized = ClaudeConfigDirResolver.normalize(path, home: home)
        let exists = isDirectory(normalized)
        let matched = exists
            ? ClaudeConfigDirResolver.serviceCandidates(for: normalized, home: home).first(where: hasKeychainItem)
            : nil
        let projects = normalized + "/projects"
        let activity = (try? fm.attributesOfItem(atPath: projects))?[.modificationDate] as? Date
        return ConfigDirCandidate(
            path: normalized,
            displayPath: ClaudeConfigDirResolver.displayPath(normalized, home: home),
            matchedService: matched,
            hasCredentialsFile: exists && fm.fileExists(atPath: normalized + "/.credentials.json"),
            lastActivity: exists ? activity : nil,
            exists: exists
        )
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}

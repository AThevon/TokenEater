import Foundation

final class MockClaudeConfigDirScanner: ClaudeConfigDirScannerProtocol, @unchecked Sendable {
    var stubbedCandidates: [ConfigDirCandidate] = []
    /// What `inspect` answers per normalized path; anything else is a folder
    /// with no login.
    var inspected: [String: ConfigDirCandidate] = [:]
    var candidatesCallCount = 0
    var inspectCallCount = 0
    var lastExcluded: Set<String> = []

    func candidates(excluding trackedPaths: Set<String>) -> [ConfigDirCandidate] {
        candidatesCallCount += 1
        lastExcluded = trackedPaths
        return stubbedCandidates.filter { !trackedPaths.contains($0.path) }
    }

    func inspect(path: String) -> ConfigDirCandidate {
        inspectCallCount += 1
        if let known = inspected[path] { return known }
        return ConfigDirCandidate(
            path: path,
            displayPath: path,
            matchedService: nil,
            hasCredentialsFile: false,
            lastActivity: nil,
            exists: true
        )
    }

    static func candidate(
        _ path: String,
        service: String? = "Claude Code-credentials-1234abcd",
        file: Bool = false,
        lastActivity: Date? = nil
    ) -> ConfigDirCandidate {
        ConfigDirCandidate(
            path: path,
            displayPath: path,
            matchedService: service,
            hasCredentialsFile: file,
            lastActivity: lastActivity,
            exists: true
        )
    }
}

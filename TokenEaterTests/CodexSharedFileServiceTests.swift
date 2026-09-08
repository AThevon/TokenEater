import Testing
import Foundation

@Suite("CodexSharedFileService")
struct CodexSharedFileServiceTests {

    private func makeSUT() -> (sut: CodexSharedFileService, root: URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-shared-\(UUID().uuidString)")
        return (CodexSharedFileService(rootDirectoryURL: root), root)
    }

    @Test("pacing margin survives usage writes and cache clearing")
    func pacingPreference() {
        let (sut, root) = makeSUT()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(sut.pacingMargin == 10)
        sut.updatePacingMargin(25)
        sut.updateAfterSync(usage: CachedCodexUsage(usage: CodexFixtures.decode(CodexFixtures.plusJSON), fetchDate: Date()), syncDate: Date())
        #expect(CodexSharedFileService(rootDirectoryURL: root).pacingMargin == 25)
        sut.clear()
        #expect(CodexSharedFileService(rootDirectoryURL: root).pacingMargin == 25)
    }

    @Test("usage survives a round trip through the file")
    func roundTrip() {
        let (sut, _) = makeSUT()
        let usage = CodexFixtures.decode(CodexFixtures.plusJSON)
        let fetchDate = Date(timeIntervalSince1970: 1_789_000_000)

        sut.updateAfterSync(usage: CachedCodexUsage(usage: usage, fetchDate: fetchDate), syncDate: fetchDate)
        sut.invalidateCache()

        #expect(sut.isConfigured)
        #expect(sut.cachedUsage?.usage == usage)
        #expect(sut.cachedUsage?.fetchDate == fetchDate)
        #expect(sut.lastSyncDate == fetchDate)
    }

    @Test("a second reader process sees what the first one wrote")
    func crossInstanceVisibility() {
        let (sut, root) = makeSUT()
        sut.updateAfterSync(
            usage: CachedCodexUsage(usage: CodexFixtures.decode(CodexFixtures.proliteJSON), fetchDate: Date()),
            syncDate: Date()
        )

        // What the widget does: its own instance, its own cache.
        let reader = CodexSharedFileService(rootDirectoryURL: root)
        #expect(reader.cachedUsage?.usage.planType == "prolite")
    }

    @Test("the enabled flag is readable on its own so the widget can explain an empty state")
    func enabledFlag() {
        let (sut, root) = makeSUT()

        #expect(!sut.isEnabled)
        sut.updateEnabled(true)
        #expect(CodexSharedFileService(rootDirectoryURL: root).isEnabled)
    }

    @Test("disabling drops the payload so no stale snapshot outlives the toggle")
    func disablingClearsPayload() {
        let (sut, root) = makeSUT()
        sut.updateEnabled(true)
        sut.updateAfterSync(
            usage: CachedCodexUsage(usage: CodexFixtures.decode(CodexFixtures.plusJSON), fetchDate: Date()),
            syncDate: Date()
        )

        sut.updateEnabled(false)

        let reader = CodexSharedFileService(rootDirectoryURL: root)
        #expect(!reader.isEnabled)
        #expect(reader.cachedUsage == nil)
        #expect(!reader.isConfigured)
    }

    @Test("clear wipes the payload but keeps the user's toggle")
    func clearKeepsToggle() {
        let (sut, root) = makeSUT()
        sut.updateEnabled(true)
        sut.updateAfterSync(
            usage: CachedCodexUsage(usage: CodexFixtures.decode(CodexFixtures.plusJSON), fetchDate: Date()),
            syncDate: Date()
        )

        sut.clear()

        let reader = CodexSharedFileService(rootDirectoryURL: root)
        #expect(reader.cachedUsage == nil)
        #expect(reader.isEnabled)
    }

    @Test("a missing file reads as empty rather than throwing")
    func missingFile() {
        let (sut, _) = makeSUT()

        #expect(sut.cachedUsage == nil)
        #expect(sut.lastSyncDate == nil)
        #expect(!sut.isConfigured)
        #expect(!sut.isEnabled)
    }

    @Test("a corrupt file reads as empty instead of taking the widget down")
    func corruptFile() throws {
        let (sut, root) = makeSUT()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{ half-writ".utf8).write(to: root.appendingPathComponent("codex.json"))

        #expect(sut.cachedUsage == nil)
        #expect(!sut.isConfigured)
    }

    @Test("a payload from a newer schema is ignored rather than half-read")
    func futureSchemaIsIgnored() throws {
        let (sut, root) = makeSUT()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let future = """
        { "schemaVersion": 99, "enabled": true, "cachedUsage": { "usage": { "plan_type": "pro" }, "fetchDate": 0 } }
        """
        try Data(future.utf8).write(to: root.appendingPathComponent("codex.json"))

        #expect(sut.cachedUsage == nil)
    }

    @Test("the file lands next to shared.json so the widget entitlement covers it")
    func fileLocation() {
        let sut = CodexSharedFileService()
        let claude = SharedFileService()

        #expect(sut.fileURL.lastPathComponent == "codex.json")
        #expect(sut.fileURL.deletingLastPathComponent() == claude.fileURL.deletingLastPathComponent())
    }
}

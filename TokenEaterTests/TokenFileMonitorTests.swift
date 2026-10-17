import Testing
import Foundation
import Combine

@Suite("Token file monitoring")
struct TokenFileMonitorTests {

    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int { lock.withLock { count } }
        func record() { lock.withLock { count += 1 } }
    }

    private func waitForEvent(_ events: Events, count: Int) async throws {
        let deadline = Date().addingTimeInterval(4)
        while events.value < count, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(events.value == count)
    }

    @Test("Codex replacement and logout emit only Codex events, including bursts")
    func codexChanges() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codex = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let auth = codex.appendingPathComponent("auth.json")
        try Data("initial".utf8).write(to: auth)
        let monitor = TokenFileMonitor(debounceInterval: 0.1, homeDirectory: home, codexHomeURL: codex)
        let codexEvents = Events()
        let claudeEvents = Events()
        let subscription = monitor.codexAuthChanged.sink { codexEvents.record() }
        let claudeSubscription = monitor.tokenChanged.sink { claudeEvents.record() }
        defer { subscription.cancel(); claudeSubscription.cancel(); monitor.stopMonitoring() }
        monitor.startMonitoring()

        try Data("replacement".utf8).write(to: auth, options: .atomic)
        try await waitForEvent(codexEvents, count: 1)
        try FileManager.default.removeItem(at: auth)
        try await waitForEvent(codexEvents, count: 2)
        for i in 0..<4 { try Data("login-\(i)".utf8).write(to: auth, options: .atomic) }
        try await waitForEvent(codexEvents, count: 3)
        #expect(claudeEvents.value == 0)
    }

    @Test("an initially missing Codex directory is discovered without restarting")
    func firstLogin() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codex = home.appendingPathComponent("custom-codex-home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let monitor = TokenFileMonitor(debounceInterval: 0.05, homeDirectory: home, codexHomeURL: codex)
        let events = Events()
        let subscription = monitor.codexAuthChanged.sink { events.record() }
        defer { subscription.cancel(); monitor.stopMonitoring() }
        monitor.startMonitoring()

        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try Data("first login".utf8).write(to: codex.appendingPathComponent("auth.json"), options: .atomic)
        try await waitForEvent(events, count: 1)
        try Data("next login".utf8).write(to: codex.appendingPathComponent("auth.json"), options: .atomic)
        try await waitForEvent(events, count: 2)
    }

    @Test("Claude changes do not emit Codex events")
    func claudeChanges() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let monitor = TokenFileMonitor(debounceInterval: 0.05, homeDirectory: home, codexHomeURL: home.appendingPathComponent(".codex"))
        let claudeEvents = Events()
        let codexEvents = Events()
        let subscription = monitor.tokenChanged.sink { claudeEvents.record() }
        let codexSubscription = monitor.codexAuthChanged.sink { codexEvents.record() }
        defer { subscription.cancel(); codexSubscription.cancel(); monitor.stopMonitoring() }
        monitor.startMonitoring()

        try Data("claude login".utf8).write(to: claude.appendingPathComponent(".credentials.json"), options: .atomic)
        try await waitForEvent(claudeEvents, count: 1)
        #expect(codexEvents.value == 0)
    }

    // MARK: - Accounts (#294)

    private final class AccountEvents: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [AccountID] = []
        var value: [AccountID] { lock.withLock { ids } }
        func record(_ id: AccountID) { lock.withLock { ids.append(id) } }
    }

    @Test("a custom main folder is watched instead of ~/.claude")
    func customMainFolder() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaultDir = home.appendingPathComponent(".claude")
        let custom = home.appendingPathComponent(".claude-perso")
        try FileManager.default.createDirectory(at: defaultDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let monitor = TokenFileMonitor(debounceInterval: 0.05, homeDirectory: home, codexHomeURL: home.appendingPathComponent(".codex"))
        let events = Events()
        let subscription = monitor.tokenChanged.sink { events.record() }
        defer { subscription.cancel(); monitor.stopMonitoring() }
        monitor.setClaudeCredentialFiles(
            main: custom.appendingPathComponent(".credentials.json"),
            includeDesktopConfig: false,
            extras: [:]
        )
        monitor.startMonitoring()

        try Data("default login".utf8).write(to: defaultDir.appendingPathComponent(".credentials.json"), options: .atomic)
        try await Task.sleep(for: .milliseconds(400))
        #expect(events.value == 0)

        try Data("perso login".utf8).write(to: custom.appendingPathComponent(".credentials.json"), options: .atomic)
        try await waitForEvent(events, count: 1)
    }

    @Test("an added account's credentials file reports that account only")
    func addedAccountFile() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let main = home.appendingPathComponent(".claude")
        let work = home.appendingPathComponent(".claude-work")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let monitor = TokenFileMonitor(debounceInterval: 0.05, homeDirectory: home, codexHomeURL: home.appendingPathComponent(".codex"))
        let mainEvents = Events()
        let accountEvents = AccountEvents()
        let a = monitor.tokenChanged.sink { mainEvents.record() }
        let b = monitor.accountTokenChanged.sink { accountEvents.record($0) }
        defer { a.cancel(); b.cancel(); monitor.stopMonitoring() }
        monitor.startMonitoring()
        // Set while monitoring: the new folder gets its own watch.
        let id = AccountID(rawValue: "acct-work")
        monitor.setClaudeCredentialFiles(
            main: main.appendingPathComponent(".credentials.json"),
            includeDesktopConfig: true,
            extras: [id: work.appendingPathComponent(".credentials.json")]
        )

        try Data("work login".utf8).write(to: work.appendingPathComponent(".credentials.json"), options: .atomic)
        let deadline = Date().addingTimeInterval(4)
        while accountEvents.value.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(accountEvents.value == [id])
        #expect(mainEvents.value == 0)
    }
}

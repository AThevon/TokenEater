import Testing
import Foundation
import Combine

@Suite("SessionStore", .serialized)
@MainActor
struct SessionStoreTests {

    private func makeStore() -> (SessionStore, MockSessionMonitorService) {
        let mock = MockSessionMonitorService()
        let store = SessionStore(monitorService: mock)
        return (store, mock)
    }

    private func makeSampleSession(
        id: String = "test-session",
        project: String = "/Users/test/MyApp",
        state: SessionState = .idle,
        lastUpdate: Date = Date(),
        model: String? = "claude-opus-4-6"
    ) -> ClaudeSession {
        ClaudeSession(
            id: id,
            projectPath: project,
            gitBranch: "main",
            model: model,
            state: state,
            lastUpdate: lastUpdate,
            startedAt: lastUpdate.addingTimeInterval(-300)
        )
    }

    @Test("the scan roots are handed to the monitor as given")
    func setRootsRelayed() {
        let (store, mock) = makeStore()
        let roots = [
            ClaudeConfigRoot(account: .main, scope: .defaultChain, home: "/Users/x"),
            ClaudeConfigRoot(account: AccountID(rawValue: "acct-w"),
                             scope: .configDir(path: "/Users/x/.claude-work", service: "S"), home: "/Users/x"),
        ]
        store.setRoots(roots)
        #expect(mock.lastRoots == roots)
    }

    @Test("an account's sessions and top model are its own; unattributed ones are the main account's")
    func sessionsPerAccount() async throws {
        let (store, mock) = makeStore()
        store.bind()
        let work = AccountID(rawValue: "acct-w")
        var mainSession = makeSampleSession(id: "m", model: "claude-opus-4-6")
        mainSession.account = .main
        let legacy = makeSampleSession(id: "legacy", model: "claude-opus-4-6")
        var workSession = makeSampleSession(id: "w", model: "claude-sonnet-4-6")
        workSession.account = work
        mock.emit([mainSession, legacy, workSession])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.activeSessions(for: .main).map(\.id) == ["m", "legacy"])
        #expect(store.activeSessions(for: work).map(\.id) == ["w"])
        #expect(store.topActiveModelName(for: work) == ModelKind(rawModel: "claude-sonnet-4-6").displayName)
        #expect(store.topActiveModelName(for: AccountID(rawValue: "acct-none")) == nil)
        #expect(store.activeSessions.count == 3)
    }

    @Test("sessions starts empty")
    func sessionsStartsEmpty() {
        let (store, _) = makeStore()
        #expect(store.sessions.isEmpty)
    }

    @Test("sessions updates when monitor emits")
    func sessionsUpdatesOnEmit() async throws {
        let (store, mock) = makeStore()
        store.bind()

        let session = makeSampleSession()
        mock.emit([session])

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.sessions.count == 1)
        #expect(store.sessions.first?.id == "test-session")
    }

    @Test("activeSessions excludes dead sessions")
    func activeSessionsExcludesDead() async throws {
        let (store, mock) = makeStore()
        store.bind()

        let alive = makeSampleSession(id: "alive", lastUpdate: Date())
        let dead = makeSampleSession(id: "dead", lastUpdate: Date().addingTimeInterval(-120))
        mock.emit([alive, dead])

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.sessions.count == 2)
        #expect(store.activeSessions.count == 1)
        #expect(store.activeSessions.first?.id == "alive")
    }

    @Test("hasActiveSessions reflects state")
    func hasActiveSessionsReflectsState() async throws {
        let (store, mock) = makeStore()
        store.bind()

        #expect(store.hasActiveSessions == false)

        mock.emit([makeSampleSession()])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.hasActiveSessions == true)
    }

    @Test("topActiveModelName is nil with no sessions")
    func topActiveModelNilWhenEmpty() {
        let (store, _) = makeStore()
        #expect(store.topActiveModelName == nil)
    }

    @Test("topActiveModelName ignores sessions without a model")
    func topActiveModelIgnoresNilModel() async throws {
        let (store, mock) = makeStore()
        store.bind()
        var s = makeSampleSession(id: "no-model")
        s.model = nil
        mock.emit([s])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.topActiveModelName == nil)
    }

    @Test("topActiveModelName returns the most frequent active model display name")
    func topActiveModelMostFrequent() async throws {
        let (store, mock) = makeStore()
        store.bind()
        let now = Date()
        var a = makeSampleSession(id: "a", lastUpdate: now); a.model = "claude-opus-4-8"
        var b = makeSampleSession(id: "b", lastUpdate: now); b.model = "claude-opus-4-8"
        var c = makeSampleSession(id: "c", lastUpdate: now); c.model = "claude-sonnet-4-6"
        mock.emit([a, b, c])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.topActiveModelName == "Opus 4.8")
    }

    @Test("topActiveModelName labels Claude 5.5 sessions with their own version")
    func topActiveModelClaude55() async throws {
        let (store, mock) = makeStore()
        store.bind()
        let now = Date()
        var a = makeSampleSession(id: "a", lastUpdate: now); a.model = "claude-opus-5-5"
        var b = makeSampleSession(id: "b", lastUpdate: now); b.model = "claude-opus-5-5[1m]"
        var c = makeSampleSession(id: "c", lastUpdate: now); c.model = "claude-sonnet-5-5"
        mock.emit([a, b, c])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.topActiveModelName == "Opus 5.5")
    }

    @Test("topActiveModelName excludes dead sessions from the tally")
    func topActiveModelExcludesDead() async throws {
        let (store, mock) = makeStore()
        store.bind()
        let now = Date()
        var alive = makeSampleSession(id: "alive", lastUpdate: now); alive.model = "claude-sonnet-4-6"
        // Two dead Opus sessions must not outvote the single live Sonnet.
        var dead1 = makeSampleSession(id: "dead1", lastUpdate: now.addingTimeInterval(-120)); dead1.model = "claude-opus-4-8"
        var dead2 = makeSampleSession(id: "dead2", lastUpdate: now.addingTimeInterval(-120)); dead2.model = "claude-opus-4-8"
        mock.emit([alive, dead1, dead2])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.topActiveModelName == "Sonnet")
    }

    // MARK: - Hidden watchers (#247)

    @Test("hideSession removes the session from overlaySessions only")
    func hideSessionFiltersOverlayOnly() async throws {
        let (store, mock) = makeStore()
        store.bind()
        let a = makeSampleSession(id: "a")
        let b = makeSampleSession(id: "b")
        mock.emit([a, b])
        try await Task.sleep(nanoseconds: 100_000_000)

        store.hideSession(id: "a")

        #expect(store.overlaySessions.map(\.id) == ["b"])
        // Monitoring consumers keep seeing the full active list.
        #expect(store.activeSessions.count == 2)
        #expect(store.hasActiveSessions == true)
    }

    @Test("overlaySessions still excludes dead sessions")
    func overlaySessionsExcludesDead() async throws {
        let (store, mock) = makeStore()
        store.bind()
        let alive = makeSampleSession(id: "alive", lastUpdate: Date())
        let dead = makeSampleSession(id: "dead", lastUpdate: Date().addingTimeInterval(-120))
        mock.emit([alive, dead])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.overlaySessions.map(\.id) == ["alive"])
    }

    @Test("hidden ids are purged when their session leaves the scan")
    func hiddenIdsPurgedWhenSessionGone() async throws {
        let (store, mock) = makeStore()
        store.bind()
        mock.emit([makeSampleSession(id: "a"), makeSampleSession(id: "b")])
        try await Task.sleep(nanoseconds: 100_000_000)

        store.hideSession(id: "a")
        #expect(store.hiddenSessionIds == ["a"])

        // "a" disappears from the scan -> the hide is forgotten, so a later
        // session reusing the same id (a resumed one) shows up again.
        mock.emit([makeSampleSession(id: "b")])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.hiddenSessionIds.isEmpty)

        mock.emit([makeSampleSession(id: "a"), makeSampleSession(id: "b")])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.overlaySessions.count == 2)
    }

    @Test("hide persists across scan ticks while the session lives")
    func hidePersistsWhileSessionLives() async throws {
        let (store, mock) = makeStore()
        store.bind()
        mock.emit([makeSampleSession(id: "a")])
        try await Task.sleep(nanoseconds: 100_000_000)

        store.hideSession(id: "a")

        mock.emit([makeSampleSession(id: "a")])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.overlaySessions.isEmpty)
        #expect(store.hiddenSessionIds == ["a"])
    }
}

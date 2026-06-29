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
}

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
        lastUpdate: Date = Date()
    ) -> ClaudeSession {
        ClaudeSession(
            id: id,
            projectPath: project,
            gitBranch: "main",
            model: "claude-opus-4-6",
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
}

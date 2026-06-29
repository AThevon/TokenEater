import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [ClaudeSession] = []

    var activeSessions: [ClaudeSession] {
        sessions.filter { !$0.isDead }
    }

    var hasActiveSessions: Bool {
        !activeSessions.isEmpty
    }

    /// Display name of the most-used model among the currently active
    /// (non-dead) Claude Code sessions. Nil when no sessions are tracked or
    /// none reported a model. Moved out of MonitoringView so it is unit-tested.
    var topActiveModelName: String? {
        let kinds = activeSessions.compactMap { $0.model }.map { ModelKind(rawModel: $0) }
        guard !kinds.isEmpty else { return nil }
        let counts = Dictionary(grouping: kinds, by: { $0 }).mapValues { $0.count }
        return counts.max { $0.value < $1.value }?.key.displayName
    }

    private let monitorService: SessionMonitorServiceProtocol
    private var cancellable: AnyCancellable?

    init(monitorService: SessionMonitorServiceProtocol = SessionMonitorService()) {
        self.monitorService = monitorService
    }

    func bind() {
        cancellable = monitorService.sessionsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] sessions in
                self?.sessions = sessions
            }
    }

    func startMonitoring() {
        bind()
        monitorService.startMonitoring()
    }

    func stopMonitoring() {
        monitorService.stopMonitoring()
        cancellable = nil
    }

    /// Push the user's watcher scan cadence to the monitor service.
    func setScanInterval(_ seconds: TimeInterval) {
        monitorService.setScanInterval(seconds)
    }

    /// Push the user's watcher visibility window to the monitor service.
    func setVisibility(_ seconds: TimeInterval) {
        monitorService.setVisibility(seconds)
    }
}

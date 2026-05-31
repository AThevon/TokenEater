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

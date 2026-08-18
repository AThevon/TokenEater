import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [ClaudeSession] = []

    /// Session ids hidden from the overlay via the watcher card's context
    /// menu, for the lifetime of each session only (#247). In-memory on
    /// purpose: nothing is persisted, so a hidden watcher reappears with the
    /// session's next run. Ids are purged as soon as their session leaves the
    /// scan, keeping the set from growing across long app uptimes.
    @Published private(set) var hiddenSessionIds: Set<String> = []

    var activeSessions: [ClaudeSession] {
        sessions.filter { !$0.isDead }
    }

    var hasActiveSessions: Bool {
        !activeSessions.isEmpty
    }

    /// What the Agent Watchers overlay actually renders: active sessions minus
    /// the user-hidden ones. Kept separate from `activeSessions`, which also
    /// feeds Monitoring (`topActiveModelName`) and must stay unfiltered.
    var overlaySessions: [ClaudeSession] {
        activeSessions.filter { !hiddenSessionIds.contains($0.id) }
    }

    /// Hide a watcher card until its session disappears from the scan.
    func hideSession(id: String) {
        hiddenSessionIds.insert(id)
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
                guard let self else { return }
                self.sessions = sessions
                // Session-scoped hide: once a hidden session leaves the scan,
                // forget it so the next session in the same project shows up.
                if !self.hiddenSessionIds.isEmpty {
                    let liveIds = Set(sessions.map { $0.id })
                    let stillLive = self.hiddenSessionIds.intersection(liveIds)
                    if stillLive != self.hiddenSessionIds {
                        self.hiddenSessionIds = stillLive
                    }
                }
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

import Foundation
import Combine

final class MockSessionMonitorService: SessionMonitorServiceProtocol {
    private let subject = CurrentValueSubject<[ClaudeSession], Never>([])
    var sessionsPublisher: AnyPublisher<[ClaudeSession], Never> {
        subject.eraseToAnyPublisher()
    }

    var startMonitoringCallCount = 0
    var stopMonitoringCallCount = 0
    var lastScanInterval: TimeInterval?
    var lastVisibility: TimeInterval?

    func startMonitoring() { startMonitoringCallCount += 1 }
    func stopMonitoring() { stopMonitoringCallCount += 1 }
    func setScanInterval(_ interval: TimeInterval) { lastScanInterval = interval }
    func setVisibility(_ freshness: TimeInterval) { lastVisibility = freshness }

    func emit(_ sessions: [ClaudeSession]) {
        subject.send(sessions)
    }
}

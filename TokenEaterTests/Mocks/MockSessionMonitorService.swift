import Foundation
import Combine

final class MockSessionMonitorService: SessionMonitorServiceProtocol {
    private let subject = CurrentValueSubject<[ClaudeSession], Never>([])
    var sessionsPublisher: AnyPublisher<[ClaudeSession], Never> {
        subject.eraseToAnyPublisher()
    }

    var startMonitoringCallCount = 0
    var stopMonitoringCallCount = 0

    func startMonitoring() { startMonitoringCallCount += 1 }
    func stopMonitoring() { stopMonitoringCallCount += 1 }

    func emit(_ sessions: [ClaudeSession]) {
        subject.send(sessions)
    }
}

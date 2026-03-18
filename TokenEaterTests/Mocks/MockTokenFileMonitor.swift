import Foundation
import Combine

final class MockTokenFileMonitor: TokenFileMonitorProtocol {
    private let subject = PassthroughSubject<Void, Never>()
    var startCallCount = 0
    var stopCallCount = 0

    var tokenChanged: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    func startMonitoring() { startCallCount += 1 }
    func stopMonitoring() { stopCallCount += 1 }

    func simulateTokenChange() { subject.send(()) }
}

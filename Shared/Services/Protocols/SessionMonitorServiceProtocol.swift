import Foundation
import Combine

protocol SessionMonitorServiceProtocol: AnyObject {
    var sessionsPublisher: AnyPublisher<[ClaudeSession], Never> { get }
    func startMonitoring()
    func stopMonitoring()
}

import Foundation
import Combine

protocol TokenFileMonitorProtocol {
    func startMonitoring()
    func stopMonitoring()
    var tokenChanged: AnyPublisher<Void, Never> { get }
}

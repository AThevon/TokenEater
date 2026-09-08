import Foundation
import Combine

protocol TokenFileMonitorProtocol {
    func startMonitoring()
    func stopMonitoring()
    var codexAuthChanged: AnyPublisher<Void, Never> { get }
    var tokenChanged: AnyPublisher<Void, Never> { get }
}

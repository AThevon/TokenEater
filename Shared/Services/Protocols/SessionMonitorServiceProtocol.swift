import Foundation
import Combine

protocol SessionMonitorServiceProtocol: AnyObject {
    var sessionsPublisher: AnyPublisher<[ClaudeSession], Never> { get }
    func startMonitoring()
    func stopMonitoring()
    /// Update the scan cadence (seconds). Takes effect live if monitoring.
    func setScanInterval(_ interval: TimeInterval)
    /// Update how long a cold session stays in the scan window (seconds).
    func setVisibility(_ freshness: TimeInterval)
    /// The Claude config folders to scan, the main account's first (#294).
    func setRoots(_ roots: [ClaudeConfigRoot])
}

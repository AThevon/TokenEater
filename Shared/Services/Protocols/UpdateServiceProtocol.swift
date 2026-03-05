import Foundation

protocol UpdateServiceProtocol: AnyObject {
    func checkForUpdates()
    var canCheckForUpdates: Bool { get }
}

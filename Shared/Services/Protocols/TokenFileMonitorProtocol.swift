import Foundation
import Combine

protocol TokenFileMonitorProtocol {
    func startMonitoring()
    func stopMonitoring()
    var codexAuthChanged: AnyPublisher<Void, Never> { get }
    /// The main account's credentials changed.
    var tokenChanged: AnyPublisher<Void, Never> { get }
    /// An added Claude account's credentials file changed.
    var accountTokenChanged: AnyPublisher<AccountID, Never> { get }
    /// Which Claude credential files to watch: the main account's (and
    /// Claude Desktop's config while its scope reads it) and each added
    /// account's. Codex is unaffected.
    func setClaudeCredentialFiles(main: URL, includeDesktopConfig: Bool, extras: [AccountID: URL])
}

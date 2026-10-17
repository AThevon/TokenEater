import Foundation
import Combine

final class MockTokenFileMonitor: TokenFileMonitorProtocol {
    private let codexSubject = PassthroughSubject<Void, Never>()
    private let subject = PassthroughSubject<Void, Never>()
    var startCallCount = 0
    var stopCallCount = 0

    var codexAuthChanged: AnyPublisher<Void, Never> { codexSubject.eraseToAnyPublisher() }
    var tokenChanged: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    func startMonitoring() { startCallCount += 1 }
    func stopMonitoring() { stopCallCount += 1 }

    func simulateCodexAuthChange() { codexSubject.send(()) }

    func simulateTokenChange() { subject.send(()) }

    private let accountSubject = PassthroughSubject<AccountID, Never>()
    var accountTokenChanged: AnyPublisher<AccountID, Never> { accountSubject.eraseToAnyPublisher() }
    func simulateAccountTokenChange(_ id: AccountID) { accountSubject.send(id) }

    var lastClaudeFiles: (main: URL, includeDesktopConfig: Bool, extras: [AccountID: URL])?
    func setClaudeCredentialFiles(main: URL, includeDesktopConfig: Bool, extras: [AccountID: URL]) {
        lastClaudeFiles = (main, includeDesktopConfig, extras)
    }
}

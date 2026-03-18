import Foundation

final class MockTokenProvider: TokenProviderProtocol, @unchecked Sendable {
    var token: String?
    var _isBootstrapped: Bool = true
    var _hasTokenSource: Bool = true
    var bootstrapError: Error?
    var bootstrapCallCount = 0
    var currentTokenCallCount = 0

    var isBootstrapped: Bool { _isBootstrapped }

    func currentToken() -> String? {
        currentTokenCallCount += 1
        return token
    }

    func hasTokenSource() -> Bool {
        _hasTokenSource
    }

    func bootstrap() throws {
        bootstrapCallCount += 1
        if let error = bootstrapError { throw error }
        _isBootstrapped = true
    }
}

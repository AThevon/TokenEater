import Testing
import Foundation

/// Stubs the transport so the client's status mapping is testable without the
/// network. Registered on an ephemeral configuration, never on `URLSession.shared`.
final class CodexStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var headers: [String: String] = [:]
    nonisolated(unsafe) static var transportError: Error?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func reset() {
        statusCode = 200
        body = Data()
        headers = [:]
        transportError = nil
        lastRequest = nil
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let error = Self.transportError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: Self.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("CodexAPIClient", .serialized)
struct CodexAPIClientTests {

    private func makeSUT() -> CodexAPIClient {
        CodexStubURLProtocol.reset()
        return CodexAPIClient(sessionProvider: { _ in CodexStubURLProtocol.session() })
    }

    // MARK: - Success

    @Test("a 200 decodes into the usage response")
    func success() async throws {
        let sut = makeSUT()
        CodexStubURLProtocol.body = Data(CodexFixtures.proliteJSON.utf8)

        let usage = try await sut.fetchUsage(credentials: CodexFixtures.credentials(), proxyConfig: nil)

        #expect(usage.planType == "prolite")
        #expect(usage.rateLimit?.primaryWindow?.usedPercent == 18)
    }

    @Test("the request carries the bearer, the account id and an honest user agent")
    func requestHeaders() async throws {
        let sut = makeSUT()
        CodexStubURLProtocol.body = Data(CodexFixtures.plusJSON.utf8)

        _ = try await sut.fetchUsage(
            credentials: CodexFixtures.credentials(accessToken: "the-token", accountId: "acct-9"),
            proxyConfig: nil
        )

        let request = try #require(CodexStubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer the-token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-9")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("TokenEater/") == true)
        // Impersonating the CLI is what attracts bot mitigation; we never do it.
        #expect(request.value(forHTTPHeaderField: "originator") == nil)
    }

    @Test("a missing account id simply omits the header")
    func omitsEmptyAccountId() async throws {
        let sut = makeSUT()
        CodexStubURLProtocol.body = Data(CodexFixtures.plusJSON.utf8)

        _ = try await sut.fetchUsage(credentials: CodexFixtures.credentials(accountId: nil), proxyConfig: nil)

        #expect(CodexStubURLProtocol.lastRequest?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
    }

    // MARK: - Error mapping

    @Test("401 maps to token expired whatever content type the body claims")
    func unauthorizedJSON() async {
        let sut = makeSUT()
        CodexStubURLProtocol.statusCode = 401
        CodexStubURLProtocol.headers = ["Content-Type": "text/plain"]
        CodexStubURLProtocol.body = Data(#"{"detail":"Could not parse your authentication token."}"#.utf8)

        await #expect(throws: APIError.self) {
            _ = try await sut.fetchUsage(credentials: CodexFixtures.credentials(), proxyConfig: nil)
        }

        do {
            _ = try await sut.fetchUsage(credentials: CodexFixtures.credentials(), proxyConfig: nil)
            Issue.record("expected a throw")
        } catch let error as APIError {
            guard case .tokenExpired(_, let status) = error else {
                Issue.record("expected tokenExpired, got \(error)")
                return
            }
            #expect(status == 401)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("403 also maps to token expired")
    func forbidden() async {
        let sut = makeSUT()
        CodexStubURLProtocol.statusCode = 403
        CodexStubURLProtocol.body = Data("<html>challenge</html>".utf8)

        do {
            _ = try await sut.fetchUsage(credentials: CodexFixtures.credentials(), proxyConfig: nil)
            Issue.record("expected a throw")
        } catch let error as APIError {
            guard case .tokenExpired(_, let status) = error else {
                Issue.record("expected tokenExpired, got \(error)")
                return
            }
            #expect(status == 403)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("429 carries the Retry-After hint when the server sends one")
    func rateLimitedWithHint() async {
        let sut = makeSUT()
        CodexStubURLProtocol.statusCode = 429
        CodexStubURLProtocol.headers = ["Retry-After": "120"]

        do {
            _ = try await sut.fetchUsage(credentials: CodexFixtures.credentials(), proxyConfig: nil)
            Issue.record("expected a throw")
        } catch let error as APIError {
            guard case .rateLimited(let retryAfter, let raw, _) = error else {
                Issue.record("expected rateLimited, got \(error)")
                return
            }
            #expect(retryAfter == 120)
            #expect(raw == "120")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("429 without a usable hint leaves the backoff to decide")
    func rateLimitedWithoutHint() async {
        let sut = makeSUT()
        CodexStubURLProtocol.statusCode = 429

        do {
            _ = try await sut.fetchUsage(credentials: CodexFixtures.credentials(), proxyConfig: nil)
            Issue.record("expected a throw")
        } catch let error as APIError {
            guard case .rateLimited(let retryAfter, _, _) = error else {
                Issue.record("expected rateLimited, got \(error)")
                return
            }
            #expect(retryAfter == nil)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("any other status maps to a plain HTTP error")
    func serverError() async {
        let sut = makeSUT()
        CodexStubURLProtocol.statusCode = 503

        do {
            _ = try await sut.fetchUsage(credentials: CodexFixtures.credentials(), proxyConfig: nil)
            Issue.record("expected a throw")
        } catch let error as APIError {
            guard case .httpError(let status, _) = error else {
                Issue.record("expected httpError, got \(error)")
                return
            }
            #expect(status == 503)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("undecodable success body is an invalid response, not a crash")
    func undecodableBody() async {
        let sut = makeSUT()
        CodexStubURLProtocol.body = Data("<html>not json</html>".utf8)

        do {
            _ = try await sut.fetchUsage(credentials: CodexFixtures.credentials(), proxyConfig: nil)
            Issue.record("expected a throw")
        } catch let error as APIError {
            guard case .invalidResponse = error else {
                Issue.record("expected invalidResponse, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("a transport failure maps to a network error carrying the reason")
    func transportFailure() async {
        let sut = makeSUT()
        CodexStubURLProtocol.transportError = URLError(.notConnectedToInternet)

        do {
            _ = try await sut.fetchUsage(credentials: CodexFixtures.credentials(), proxyConfig: nil)
            Issue.record("expected a throw")
        } catch let error as APIError {
            guard case .networkError = error else {
                Issue.record("expected networkError, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    // MARK: - Connection test

    @Test("the connection test reports the first window on success")
    func connectionTestSuccess() async {
        let sut = makeSUT()
        CodexStubURLProtocol.body = Data(CodexFixtures.proliteJSON.utf8)

        let result = await sut.testConnection(credentials: CodexFixtures.credentials(), proxyConfig: nil)

        #expect(result.success)
    }

    @Test("a throttled connection test still counts as connected")
    func connectionTestRateLimited() async {
        let sut = makeSUT()
        CodexStubURLProtocol.statusCode = 429

        let result = await sut.testConnection(credentials: CodexFixtures.credentials(), proxyConfig: nil)

        #expect(result.success)
    }

    @Test("an expired token fails the connection test")
    func connectionTestExpired() async {
        let sut = makeSUT()
        CodexStubURLProtocol.statusCode = 401

        let result = await sut.testConnection(credentials: CodexFixtures.credentials(), proxyConfig: nil)

        #expect(!result.success)
    }

    @Test("a plan with no windows is reported as connected, not as a failure")
    func connectionTestNoWindows() async {
        let sut = makeSUT()
        CodexStubURLProtocol.body = Data(CodexFixtures.apiKeyJSON.utf8)

        let result = await sut.testConnection(credentials: CodexFixtures.credentials(), proxyConfig: nil)

        #expect(result.success)
    }
}

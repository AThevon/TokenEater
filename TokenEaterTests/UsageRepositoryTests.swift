import Testing
import Foundation

@Suite("UsageRepository")
struct UsageRepositoryTests {

    // MARK: - Helpers

    private func makeSUT() -> (
        repo: UsageRepository,
        api: MockAPIClient,
        keychain: MockKeychainService,
        sharedFile: MockSharedFileService
    ) {
        let api = MockAPIClient()
        let keychain = MockKeychainService()
        let sharedFile = MockSharedFileService()
        let repo = UsageRepository(
            apiClient: api,
            keychainService: keychain,
            sharedFileService: sharedFile
        )
        return (repo, api, keychain, sharedFile)
    }

    // MARK: - syncKeychainToken (interactive)

    @Test("syncKeychainToken copies token to shared file")
    func syncKeychainTokenCopiesToSharedFile() {
        let (repo, _, keychain, sharedFile) = makeSUT()
        keychain.storedToken = "tok"

        repo.syncKeychainToken()

        #expect(sharedFile._oauthToken == "tok")
    }

    @Test("syncKeychainToken does nothing when no token")
    func syncKeychainTokenDoesNothingWhenNoToken() {
        let (repo, _, _, sharedFile) = makeSUT()

        repo.syncKeychainToken()

        #expect(sharedFile._oauthToken == nil)
    }

    // MARK: - syncKeychainTokenSilently

    @Test("syncKeychainTokenSilently copies token to shared file")
    func syncKeychainTokenSilentlyCopiesToSharedFile() {
        let (repo, _, keychain, sharedFile) = makeSUT()
        keychain.storedToken = "silent-tok"

        repo.syncKeychainTokenSilently()

        #expect(sharedFile._oauthToken == "silent-tok")
    }

    @Test("syncKeychainTokenSilently does nothing when no token")
    func syncKeychainTokenSilentlyDoesNothingWhenNoToken() {
        let (repo, _, _, sharedFile) = makeSUT()

        repo.syncKeychainTokenSilently()

        #expect(sharedFile._oauthToken == nil)
    }

    // MARK: - currentToken

    @Test("currentToken delegates to shared file oauthToken")
    func currentTokenDelegatesToSharedFile() {
        let (repo, _, _, sharedFile) = makeSUT()
        sharedFile._oauthToken = "my-token"

        #expect(repo.currentToken == "my-token")
    }

    @Test("currentToken is nil when shared file has no token")
    func currentTokenIsNilWhenNoToken() {
        let (repo, _, _, _) = makeSUT()

        #expect(repo.currentToken == nil)
    }

    // MARK: - isConfigured

    @Test("isConfigured true when token set")
    func isConfiguredTrueWhenTokenSet() {
        let (repo, _, _, sharedFile) = makeSUT()
        sharedFile._oauthToken = "x"

        #expect(repo.isConfigured == true)
    }

    @Test("isConfigured false when no token")
    func isConfiguredFalseWhenNoToken() {
        let (repo, _, _, _) = makeSUT()

        #expect(repo.isConfigured == false)
    }

    // MARK: - refreshUsage

    @Test("refreshUsage fetches from API and writes to shared file")
    func refreshUsageFetchesAndWrites() async throws {
        let (repo, api, _, sharedFile) = makeSUT()
        sharedFile._oauthToken = "tok"
        api.stubbedUsage = .fixture(fiveHourUtil: 10, sevenDayUtil: 20, sonnetUtil: 30)

        let response = try await repo.refreshUsage(proxyConfig: nil)

        #expect(api.fetchCallCount == 1)
        #expect(sharedFile.updateAfterSyncCallCount == 1)
        #expect(response.fiveHour?.utilization == 10)
    }

    @Test("refreshUsage throws noToken when not configured")
    func refreshUsageThrowsNoToken() async {
        let (repo, _, _, _) = makeSUT()

        do {
            _ = try await repo.refreshUsage(proxyConfig: nil)
            Issue.record("Expected APIError.noToken")
        } catch let error as APIError {
            guard case .noToken = error else {
                Issue.record("Expected .noToken, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test("refreshUsage propagates non-tokenExpired API errors")
    func refreshUsagePropagatesAPIErrors() async {
        let (repo, api, _, sharedFile) = makeSUT()
        sharedFile._oauthToken = "tok"
        api.stubbedError = APIError.invalidResponse

        do {
            _ = try await repo.refreshUsage(proxyConfig: nil)
            Issue.record("Expected APIError.invalidResponse")
        } catch let error as APIError {
            guard case .invalidResponse = error else {
                Issue.record("Expected .invalidResponse, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    // MARK: - refreshUsage — token recovery

    @Test("refreshUsage retries with new token when tokenExpired and keychain has fresh token")
    func refreshUsageRetriesWithNewToken() async throws {
        let (_, _, keychain, sharedFile) = makeSUT()
        sharedFile._oauthToken = "old-token"
        keychain.storedToken = "fresh-token"

        // The API will throw tokenExpired on the first call with "old-token",
        // then succeed on the second call with "fresh-token".
        let smartAPI = TokenRecoveryMockAPIClient()
        smartAPI.failToken = "old-token"
        smartAPI.successUsage = .fixture(fiveHourUtil: 99)

        let smartRepo = UsageRepository(
            apiClient: smartAPI,
            keychainService: keychain,
            sharedFileService: sharedFile
        )

        let response = try await smartRepo.refreshUsage(proxyConfig: nil)

        #expect(response.fiveHour?.utilization == 99)
        #expect(sharedFile._oauthToken == "fresh-token")
        #expect(smartAPI.callCount == 2)
    }

    @Test("refreshUsage throws keychainLocked when keychain inaccessible during recovery")
    func refreshUsageThrowsKeychainLockedOnRecovery() async {
        let (_, _, keychain, sharedFile) = makeSUT()
        sharedFile._oauthToken = "old-token"
        keychain.storedToken = nil // Keychain inaccessible

        let failingAPI = MockAPIClient()
        failingAPI.stubbedError = APIError.tokenExpired

        let repo = UsageRepository(
            apiClient: failingAPI,
            keychainService: keychain,
            sharedFileService: sharedFile
        )

        do {
            _ = try await repo.refreshUsage(proxyConfig: nil)
            Issue.record("Expected APIError.keychainLocked")
        } catch let error as APIError {
            guard case .keychainLocked = error else {
                Issue.record("Expected .keychainLocked, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    @Test("refreshUsage throws tokenExpired when keychain has same token during recovery")
    func refreshUsageThrowsTokenExpiredWhenSameToken() async {
        let (_, _, keychain, sharedFile) = makeSUT()
        sharedFile._oauthToken = "same-token"
        keychain.storedToken = "same-token"

        let failingAPI = MockAPIClient()
        failingAPI.stubbedError = APIError.tokenExpired

        let repo = UsageRepository(
            apiClient: failingAPI,
            keychainService: keychain,
            sharedFileService: sharedFile
        )

        do {
            _ = try await repo.refreshUsage(proxyConfig: nil)
            Issue.record("Expected APIError.tokenExpired")
        } catch let error as APIError {
            guard case .tokenExpired = error else {
                Issue.record("Expected .tokenExpired, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected APIError, got \(error)")
        }
    }

    // MARK: - testConnection

    @Test("testConnection returns failure when no token")
    func testConnectionFailsWithoutToken() async {
        let (repo, _, _, _) = makeSUT()

        let result = await repo.testConnection(proxyConfig: nil)

        #expect(result.success == false)
    }

    @Test("testConnection delegates to API when token exists")
    func testConnectionDelegatesToAPI() async {
        let (repo, api, _, sharedFile) = makeSUT()
        sharedFile._oauthToken = "tok"
        api.stubbedConnectionResult = ConnectionTestResult(success: true, message: "Connected")

        let result = await repo.testConnection(proxyConfig: nil)

        #expect(result.success == true)
        #expect(result.message == "Connected")
    }

    // MARK: - cachedUsage

    @Test("cachedUsage delegates to shared file")
    func cachedUsageDelegatesToSharedFile() {
        let (repo, _, _, sharedFile) = makeSUT()
        let usage = CachedUsage(usage: .fixture(), fetchDate: Date())
        sharedFile._cachedUsage = usage

        let cached = repo.cachedUsage
        #expect(cached != nil)
        #expect(cached?.usage.fiveHour?.utilization == usage.usage.fiveHour?.utilization)
    }
}

// MARK: - Specialized mock for token recovery testing

private final class TokenRecoveryMockAPIClient: APIClientProtocol, @unchecked Sendable {
    var failToken: String?
    var successUsage: UsageResponse = UsageResponse()
    var callCount = 0

    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        callCount += 1
        if token == failToken {
            throw APIError.tokenExpired
        }
        return successUsage
    }

    func testConnection(token: String, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        ConnectionTestResult(success: true, message: "OK")
    }
}

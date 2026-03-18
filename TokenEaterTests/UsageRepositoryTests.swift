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

    /// Helper: configure the repo with a token via syncCredentialsFile.
    private func makeSUTWithToken(_ token: String) -> (
        repo: UsageRepository,
        api: MockAPIClient,
        keychain: MockKeychainService,
        sharedFile: MockSharedFileService
    ) {
        let (repo, api, keychain, sharedFile) = makeSUT()
        keychain.storedToken = token
        repo.syncCredentialsFile()
        return (repo, api, keychain, sharedFile)
    }

    // MARK: - syncCredentialsFile

    @Test("syncCredentialsFile copies credentials file token to in-memory cache")
    func syncCredentialsFileCopiesToMemory() {
        let (repo, _, keychain, _) = makeSUT()
        keychain.storedToken = "cred-tok"

        repo.syncCredentialsFile()

        #expect(repo.currentToken == "cred-tok")
    }

    @Test("syncCredentialsFile does nothing when no credentials file token")
    func syncCredentialsFileDoesNothingWhenNoToken() {
        let (repo, _, _, _) = makeSUT()

        repo.syncCredentialsFile()

        #expect(repo.currentToken == nil)
    }

    // MARK: - syncKeychainSilently

    @Test("syncKeychainSilently copies token to in-memory cache")
    func syncKeychainSilentlyCopiesToMemory() {
        let (repo, _, keychain, _) = makeSUT()
        keychain.storedToken = "kc-tok"

        repo.syncKeychainSilently()

        #expect(repo.currentToken == "kc-tok")
    }

    @Test("syncKeychainSilently does nothing when no token")
    func syncKeychainSilentlyDoesNothingWhenNoToken() {
        let (repo, _, _, _) = makeSUT()

        repo.syncKeychainSilently()

        #expect(repo.currentToken == nil)
    }

    // MARK: - currentToken

    @Test("currentToken returns token after sync")
    func currentTokenReturnsTokenAfterSync() {
        let (repo, _, keychain, _) = makeSUT()
        keychain.storedToken = "my-token"
        repo.syncCredentialsFile()

        #expect(repo.currentToken == "my-token")
    }

    @Test("currentToken is nil when no sync performed")
    func currentTokenIsNilWhenNoToken() {
        let (repo, _, _, _) = makeSUT()

        #expect(repo.currentToken == nil)
    }

    // MARK: - isConfigured

    @Test("isConfigured true when token set")
    func isConfiguredTrueWhenTokenSet() {
        let (repo, _, keychain, _) = makeSUT()
        keychain.storedToken = "x"
        repo.syncCredentialsFile()

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
        let (repo, api, _, sharedFile) = makeSUTWithToken("tok")
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
        let (repo, api, _, _) = makeSUTWithToken("tok")
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

    @Test("refreshUsage retries with new token when tokenExpired and credentials file has fresh token")
    func refreshUsageRetriesWithNewToken() async throws {
        let keychain = MockKeychainService()
        let sharedFile = MockSharedFileService()
        keychain.storedToken = "old-token"

        let smartAPI = TokenRecoveryMockAPIClient()
        smartAPI.failToken = "old-token"
        smartAPI.successUsage = .fixture(fiveHourUtil: 99)

        let smartRepo = UsageRepository(
            apiClient: smartAPI,
            keychainService: keychain,
            sharedFileService: sharedFile
        )
        smartRepo.syncCredentialsFile()

        // Now switch the keychain to have the fresh token for recovery
        keychain.storedToken = "fresh-token"

        let response = try await smartRepo.refreshUsage(proxyConfig: nil)

        #expect(response.fiveHour?.utilization == 99)
        #expect(smartRepo.currentToken == "fresh-token")
        #expect(smartAPI.callCount == 2)
    }

    @Test("refreshUsage throws tokenExpired when no fresh token available during recovery")
    func refreshUsageThrowsTokenExpiredOnRecovery() async {
        let keychain = MockKeychainService()
        let sharedFile = MockSharedFileService()
        keychain.storedToken = "old-token"

        let failingAPI = MockAPIClient()
        failingAPI.stubbedError = APIError.tokenExpired

        let repo = UsageRepository(
            apiClient: failingAPI,
            keychainService: keychain,
            sharedFileService: sharedFile
        )
        repo.syncCredentialsFile()

        // No fresh token available — credentials file returns nil
        keychain.storedToken = nil

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

    @Test("refreshUsage throws tokenExpired when credentials file has same token during recovery")
    func refreshUsageThrowsTokenExpiredWhenSameToken() async {
        let keychain = MockKeychainService()
        let sharedFile = MockSharedFileService()
        keychain.storedToken = "same-token"

        let failingAPI = MockAPIClient()
        failingAPI.stubbedError = APIError.tokenExpired

        let repo = UsageRepository(
            apiClient: failingAPI,
            keychainService: keychain,
            sharedFileService: sharedFile
        )
        repo.syncCredentialsFile()

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
        let (repo, api, _, _) = makeSUTWithToken("tok")
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

    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
        if token == failToken {
            throw APIError.tokenExpired
        }
        return .fixture()
    }

    func testConnection(token: String, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        ConnectionTestResult(success: true, message: "OK")
    }
}

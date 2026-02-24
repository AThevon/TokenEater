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

    // MARK: - syncKeychainToken

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

    // MARK: - isConfigured

    @Test("isConfigured delegates to shared file – true when token set")
    func isConfiguredTrueWhenTokenSet() {
        let (repo, _, _, sharedFile) = makeSUT()
        sharedFile._oauthToken = "x"

        #expect(repo.isConfigured == true)
    }

    @Test("isConfigured delegates to shared file – false when no token")
    func isConfiguredFalseWhenNoToken() {
        let (repo, _, _, sharedFile) = makeSUT()
        sharedFile._oauthToken = nil

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

        await #expect(throws: APIError.self) {
            try await repo.refreshUsage(proxyConfig: nil)
        }
    }

    @Test("refreshUsage propagates API errors")
    func refreshUsagePropagatesAPIErrors() async {
        let (repo, api, _, sharedFile) = makeSUT()
        sharedFile._oauthToken = "tok"
        api.stubbedError = APIError.invalidResponse

        await #expect(throws: APIError.self) {
            try await repo.refreshUsage(proxyConfig: nil)
        }
    }

    // MARK: - testConnection

    @Test("testConnection returns failure when no token")
    func testConnectionFailsWithoutToken() async {
        let (repo, _, _, _) = makeSUT()

        let result = await repo.testConnection(proxyConfig: nil)

        #expect(result.success == false)
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

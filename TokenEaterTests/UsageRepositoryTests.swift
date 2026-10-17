import Testing
import Foundation

@Suite("UsageRepository")
struct UsageRepositoryTests {

    // MARK: - Helpers

    private func makeSUT() -> (
        repo: UsageRepository,
        api: MockAPIClient,
        sharedFile: MockSharedFileService
    ) {
        let api = MockAPIClient()
        let sharedFile = MockSharedFileService()
        let repo = UsageRepository(
            apiClient: api,
            sharedFileService: sharedFile
        )
        return (repo, api, sharedFile)
    }

    // MARK: - fetchUsage / saveUsage

    @Test("fetchUsage calls the API and writes nothing")
    func fetchUsageWritesNothing() async throws {
        let (repo, api, sharedFile) = makeSUT()
        api.stubbedUsage = .fixture(fiveHourUtil: 42)

        let response = try await repo.fetchUsage(token: "tok-123", proxyConfig: nil)

        #expect(api.fetchCallCount == 1)
        #expect(sharedFile.updateAfterSyncCallCount == 0)
        #expect(response.fiveHour?.utilization == 42)
    }

    @Test("fetchUsage throws API errors through")
    func fetchUsageThrowsAPIErrors() async {
        let (repo, api, _) = makeSUT()
        api.stubbedError = APIError.invalidResponse(endpoint: "/api/oauth/usage")

        do {
            _ = try await repo.fetchUsage(token: "tok", proxyConfig: nil)
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

    @Test("saveUsage writes the usage to the shared file")
    func saveUsageWrites() {
        let (repo, _, sharedFile) = makeSUT()
        repo.saveUsage(.fixture(fiveHourUtil: 42), fetchedAt: Date())
        #expect(sharedFile.updateAfterSyncCallCount == 1)
    }

    // MARK: - fetchProfile

    @Test("fetchProfile calls API and returns result")
    func fetchProfileReturnsResult() async throws {
        let (repo, api, _) = makeSUT()
        api.stubbedProfile = .fixture(fullName: "Alice")

        let profile = try await repo.fetchProfile(token: "tok", proxyConfig: nil)

        #expect(profile.account.fullName == "Alice")
    }

    @Test("fetchProfile throws API errors through")
    func fetchProfileThrowsAPIErrors() async {
        let (repo, api, _) = makeSUT()
        api.stubbedError = APIError.tokenExpired(endpoint: "/api/oauth/profile", statusCode: 401)

        do {
            _ = try await repo.fetchProfile(token: "tok", proxyConfig: nil)
            Issue.record("Expected error")
        } catch {
            // Expected
        }
    }

    // MARK: - testConnection

    @Test("testConnection calls API without writing to shared file")
    func testConnectionDoesNotWriteToSharedFile() async throws {
        let (repo, api, sharedFile) = makeSUT()
        api.stubbedUsage = .fixture(fiveHourUtil: 10)

        let response = try await repo.testConnection(token: "tok", proxyConfig: nil)

        #expect(response.fiveHour?.utilization == 10)
        #expect(sharedFile.updateAfterSyncCallCount == 0)
    }

    @Test("testConnection throws API errors through")
    func testConnectionThrowsAPIErrors() async {
        let (repo, api, _) = makeSUT()
        api.stubbedError = APIError.noToken

        do {
            _ = try await repo.testConnection(token: "tok", proxyConfig: nil)
            Issue.record("Expected error")
        } catch {
            // Expected
        }
    }
}

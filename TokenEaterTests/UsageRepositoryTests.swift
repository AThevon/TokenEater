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

    // MARK: - refreshUsage

    @Test("refreshUsage calls API and writes to shared file on success")
    func refreshUsageCallsAPIAndWritesToSharedFile() async throws {
        let (repo, api, sharedFile) = makeSUT()
        api.stubbedUsage = .fixture(fiveHourUtil: 42)

        let response = try await repo.refreshUsage(token: "tok-123", proxyConfig: nil)

        #expect(api.fetchCallCount == 1)
        #expect(sharedFile.updateAfterSyncCallCount == 1)
        #expect(response.fiveHour?.utilization == 42)
    }

    @Test("refreshUsage throws API errors through")
    func refreshUsageThrowsAPIErrors() async {
        let (repo, api, _) = makeSUT()
        api.stubbedError = APIError.invalidResponse

        do {
            _ = try await repo.refreshUsage(token: "tok", proxyConfig: nil)
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

    @Test("refreshUsage does not write to shared file on failure")
    func refreshUsageDoesNotWriteOnFailure() async {
        let (repo, api, sharedFile) = makeSUT()
        api.stubbedError = APIError.tokenExpired

        _ = try? await repo.refreshUsage(token: "tok", proxyConfig: nil)

        #expect(sharedFile.updateAfterSyncCallCount == 0)
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
        api.stubbedError = APIError.tokenExpired

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

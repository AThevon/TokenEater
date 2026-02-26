import Testing
import Foundation

@Suite("UsageRepository – Profile")
struct UsageRepositoryProfileTests {

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

    @Test("fetchProfile returns profile when token exists")
    func fetchProfileSuccess() async throws {
        let (repo, api, _, sharedFile) = makeSUT()
        sharedFile._oauthToken = "valid-token"
        let expected = ProfileResponse.fixture(fullName: "Alice")
        api.stubbedProfile = expected

        let profile = try await repo.fetchProfile(proxyConfig: nil)
        #expect(profile.account.fullName == "Alice")
    }

    @Test("fetchProfile throws noToken when no token")
    func fetchProfileNoToken() async {
        let (repo, _, _, _) = makeSUT()

        do {
            _ = try await repo.fetchProfile(proxyConfig: nil)
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
}

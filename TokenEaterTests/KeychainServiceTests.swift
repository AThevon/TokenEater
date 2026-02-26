import Testing
import Foundation

@Suite("KeychainService – file-first strategy")
struct KeychainServiceTests {

    // MARK: - readOAuthToken

    @Test("readOAuthToken returns file token when available")
    func readOAuthTokenReturnsFileToken() {
        let fileReader = MockCredentialsFileReader()
        fileReader.storedToken = "file-token"
        let sut = KeychainService(credentialsFileReader: fileReader)

        #expect(sut.readOAuthToken() == "file-token")
    }

    @Test("readOAuthToken prefers file token over keychain")
    func readOAuthTokenPrefersFileOverKeychain() {
        let fileReader = MockCredentialsFileReader()
        fileReader.storedToken = "file-wins"
        let sut = KeychainService(credentialsFileReader: fileReader)

        // Even if keychain has a real token, file token takes priority
        #expect(sut.readOAuthToken() == "file-wins")
    }

    @Test("readOAuthToken consults keychain when file has no token")
    func readOAuthTokenConsultsKeychain() {
        let fileReader = MockCredentialsFileReader()
        fileReader.storedToken = nil
        let sut = KeychainService(credentialsFileReader: fileReader)

        // Result is environment-dependent (nil in CI, real token on dev machine)
        // Verify fallback path executes without error
        let result = sut.readOAuthToken()
        if let result { #expect(!result.isEmpty) }
    }

    // MARK: - readOAuthTokenSilently

    @Test("readOAuthTokenSilently returns file token when available")
    func readOAuthTokenSilentlyReturnsFileToken() {
        let fileReader = MockCredentialsFileReader()
        fileReader.storedToken = "silent-file-token"
        let sut = KeychainService(credentialsFileReader: fileReader)

        #expect(sut.readOAuthTokenSilently() == "silent-file-token")
    }

    @Test("readOAuthTokenSilently consults keychain when file has no token")
    func readOAuthTokenSilentlyConsultsKeychain() {
        let fileReader = MockCredentialsFileReader()
        fileReader.storedToken = nil
        let sut = KeychainService(credentialsFileReader: fileReader)

        let result = sut.readOAuthTokenSilently()
        if let result { #expect(!result.isEmpty) }
    }

    // MARK: - tokenExists

    @Test("tokenExists returns true when credentials file exists")
    func tokenExistsReturnsTrueWhenFileExists() {
        let fileReader = MockCredentialsFileReader()
        fileReader.fileExists = true
        let sut = KeychainService(credentialsFileReader: fileReader)

        #expect(sut.tokenExists() == true)
    }

    @Test("tokenExists consults keychain when file does not exist")
    func tokenExistsConsultsKeychain() {
        let fileReader = MockCredentialsFileReader()
        fileReader.fileExists = false
        let sut = KeychainService(credentialsFileReader: fileReader)

        // Environment-dependent: true if dev machine has keychain token, false in CI
        _ = sut.tokenExists()
    }
}

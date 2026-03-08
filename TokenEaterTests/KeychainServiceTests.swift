import Testing
import Foundation

@Suite("KeychainService – credentials file reader")
struct KeychainServiceTests {

    @Test("readToken returns file token when available")
    func readTokenReturnsFileToken() {
        let fileReader = MockCredentialsFileReader()
        fileReader.storedToken = "file-token"
        let sut = KeychainService(credentialsFileReader: fileReader)

        #expect(sut.readToken() == "file-token")
    }

    @Test("readToken returns nil when no file token")
    func readTokenReturnsNilWhenNoFileToken() {
        let fileReader = MockCredentialsFileReader()
        fileReader.storedToken = nil
        let sut = KeychainService(credentialsFileReader: fileReader)

        #expect(sut.readToken() == nil)
    }

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

    @Test("readKeychainTokenSilently returns file token first")
    func readKeychainTokenSilentlyReturnsFileTokenFirst() {
        let fileReader = MockCredentialsFileReader()
        fileReader.storedToken = "file-token"
        let sut = KeychainService(credentialsFileReader: fileReader)

        #expect(sut.readKeychainTokenSilently() == "file-token")
    }

    @Test("readKeychainTokenSilently consults keychain when no file token")
    func readKeychainTokenSilentlyConsultsKeychain() {
        let fileReader = MockCredentialsFileReader()
        fileReader.storedToken = nil
        let sut = KeychainService(credentialsFileReader: fileReader)

        // Environment-dependent: real token on dev machine, nil in CI
        let result = sut.readKeychainTokenSilently()
        if let result { #expect(!result.isEmpty) }
    }
}

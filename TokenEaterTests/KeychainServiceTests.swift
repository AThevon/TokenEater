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

    @Test("tokenExists returns false when credentials file does not exist")
    func tokenExistsReturnsFalseWhenNoFile() {
        let fileReader = MockCredentialsFileReader()
        fileReader.fileExists = false
        let sut = KeychainService(credentialsFileReader: fileReader)

        #expect(sut.tokenExists() == false)
    }
}

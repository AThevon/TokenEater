import Testing
import Foundation

@Suite("CredentialsFileReader")
struct CredentialsFileReaderTests {

    // MARK: - readToken

    @Test("readToken returns token from valid credentials file")
    func readTokenReturnsTokenFromValidFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent(".credentials.json").path
        let json = """
        {"claudeAiOauth":{"accessToken":"test-token-123"}}
        """
        FileManager.default.createFile(atPath: filePath, contents: json.data(using: .utf8))

        let reader = CredentialsFileReader(filePath: filePath)
        #expect(reader.readToken() == "test-token-123")
    }

    @Test("readToken returns nil when file does not exist")
    func readTokenReturnsNilWhenFileDoesNotExist() {
        let reader = CredentialsFileReader(filePath: "/nonexistent/path/.credentials.json")
        #expect(reader.readToken() == nil)
    }

    @Test("readToken returns nil when JSON is malformed")
    func readTokenReturnsNilWhenJSONMalformed() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent(".credentials.json").path
        FileManager.default.createFile(atPath: filePath, contents: "not json".data(using: .utf8))

        let reader = CredentialsFileReader(filePath: filePath)
        #expect(reader.readToken() == nil)
    }

    @Test("readToken returns nil when accessToken is missing")
    func readTokenReturnsNilWhenAccessTokenMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent(".credentials.json").path
        let json = """
        {"claudeAiOauth":{"refreshToken":"abc"}}
        """
        FileManager.default.createFile(atPath: filePath, contents: json.data(using: .utf8))

        let reader = CredentialsFileReader(filePath: filePath)
        #expect(reader.readToken() == nil)
    }

    @Test("readToken returns nil when accessToken is empty")
    func readTokenReturnsNilWhenAccessTokenEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent(".credentials.json").path
        let json = """
        {"claudeAiOauth":{"accessToken":""}}
        """
        FileManager.default.createFile(atPath: filePath, contents: json.data(using: .utf8))

        let reader = CredentialsFileReader(filePath: filePath)
        #expect(reader.readToken() == nil)
    }

    // MARK: - tokenExists

    @Test("tokenExists returns true when file exists")
    func tokenExistsReturnsTrueWhenFileExists() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent(".credentials.json").path
        FileManager.default.createFile(atPath: filePath, contents: "{}".data(using: .utf8))

        let reader = CredentialsFileReader(filePath: filePath)
        #expect(reader.tokenExists() == true)
    }

    @Test("tokenExists returns false when file does not exist")
    func tokenExistsReturnsFalseWhenFileDoesNotExist() {
        let reader = CredentialsFileReader(filePath: "/nonexistent/path/.credentials.json")
        #expect(reader.tokenExists() == false)
    }
}

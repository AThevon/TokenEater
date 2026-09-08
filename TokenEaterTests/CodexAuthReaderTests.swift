import Testing
import Foundation

@Suite("CodexAuthReader")
struct CodexAuthReaderTests {

    // MARK: - Helpers

    private func makeHome(_ contents: String?, file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-auth-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if let contents {
            try contents.write(to: home.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        }
        return home
    }

    private func reader(home: URL) -> CodexAuthReader {
        CodexAuthReader(environment: ["CODEX_HOME": home.path])
    }

    private func authJSON(mode: String? = "chatgpt", accessToken: String?, accountId: String? = "acct-1") -> String {
        var tokens: [String: Any] = [:]
        if let accessToken { tokens["access_token"] = accessToken }
        if let accountId { tokens["account_id"] = accountId }
        tokens["id_token"] = "header.payload.sig"
        tokens["refresh_token"] = "refresh-secret"
        var root: [String: Any] = ["tokens": tokens, "last_refresh": "2026-09-03T10:51:05.889197Z"]
        if let mode { root["auth_mode"] = mode }
        root["OPENAI_API_KEY"] = NSNull()
        return String(decoding: try! JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    }

    // MARK: - States

    @Test("a ChatGPT login yields trackable credentials with claims from the token")
    func chatGPTLogin() throws {
        let expiry = Date().addingTimeInterval(864_000)
        let token = CodexFixtures.jwt(planType: "prolite", accountId: "acct-1", exp: expiry)
        let home = try makeHome(authJSON(accessToken: token))
        let sut = reader(home: home)

        let credentials = try #require(sut.readCredentials())
        #expect(credentials.accessToken == token)
        #expect(credentials.accountId == "acct-1")
        #expect(credentials.planType == "prolite")
        #expect(credentials.expiresAt?.timeIntervalSince1970 == expiry.timeIntervalSince1970)
        #expect(credentials.lastRefresh != nil)
        #expect(sut.authState().isTrackable)
    }

    @Test("an API-key login is reported as untrackable rather than as an error")
    func apiKeyLogin() throws {
        let json = """
        { "auth_mode": "apikey", "OPENAI_API_KEY": "sk-test", "tokens": null }
        """
        let sut = reader(home: try makeHome(json))

        #expect(sut.readCredentials() == nil)
        #expect(sut.authState() == .apiKeyOnly)
    }

    @Test("a missing Codex directory is 'not installed', a missing file is 'no credentials'")
    func missingPaths() throws {
        let emptyHome = try makeHome(nil)
        #expect(reader(home: emptyHome).authState() == .noCredentials)

        let absent = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("codex-none-\(UUID().uuidString)")
        #expect(reader(home: absent).authState() == .notInstalled)
        #expect(reader(home: absent).readCredentials() == nil)
    }

    @Test("malformed or empty JSON degrades to 'no credentials'")
    func malformedFile() throws {
        #expect(reader(home: try makeHome("{ not json")).authState() == .noCredentials)
        #expect(reader(home: try makeHome("")).authState() == .noCredentials)
        #expect(reader(home: try makeHome("[]")).authState() == .noCredentials)
        #expect(reader(home: try makeHome(authJSON(accessToken: nil, accountId: nil))).authState() == .noCredentials)
    }

    @Test("a ChatGPT-mode file without a token reads as logged out, not as API-key mode")
    func chatGPTModeWithoutToken() throws {
        // Sending this user to "API keys have no limits" would be the wrong fix;
        // they just need to log in again.
        let sut = reader(home: try makeHome(authJSON(mode: "chatgpt", accessToken: nil, accountId: nil)))

        #expect(sut.authState() == .noCredentials)
    }

    @Test("an older file with tokens but no auth_mode is treated as a ChatGPT login")
    func missingAuthMode() throws {
        let sut = reader(home: try makeHome(authJSON(mode: nil, accessToken: CodexFixtures.jwt())))
        #expect(sut.readCredentials() != nil)
    }

    @Test("the account id falls back to the token claim when the file omits it")
    func accountIdFromClaims() throws {
        let token = CodexFixtures.jwt(accountId: "from-claim")
        let sut = reader(home: try makeHome(authJSON(accessToken: token, accountId: nil)))

        #expect(sut.readCredentials()?.accountId == "from-claim")
    }

    // MARK: - Path resolution

    @Test("an explicit override wins over the environment")
    func overrideWinsOverEnvironment() throws {
        let overrideHome = try makeHome(authJSON(accessToken: CodexFixtures.jwt()))
        let envHome = try makeHome(nil)
        let sut = CodexAuthReader(environment: ["CODEX_HOME": envHome.path], overridePath: overrideHome.path)

        #expect(sut.codexHomeURL.path == overrideHome.path)
        #expect(sut.readCredentials() != nil)
    }

    @Test("with no override and no environment the reader points at ~/.codex")
    func defaultPath() {
        let sut = CodexAuthReader(environment: [:])
        #expect(sut.codexHomeURL.lastPathComponent == ".codex")
        #expect(sut.authFileURL.lastPathComponent == "auth.json")
    }

    @Test("a tilde in the override is expanded")
    func tildeExpansion() {
        let sut = CodexAuthReader(environment: [:], overridePath: "~/some-codex-home")
        #expect(!sut.codexHomeURL.path.contains("~"))
        #expect(sut.codexHomeURL.path.hasSuffix("some-codex-home"))
    }

    // MARK: - Expiry

    @Test("expiry is read from the token, not from last_refresh")
    func expiry() throws {
        let past = Date().addingTimeInterval(-3_600)
        let sut = reader(home: try makeHome(authJSON(accessToken: CodexFixtures.jwt(exp: past))))

        #expect(sut.readCredentials()?.isExpired() == true)
        #expect(sut.authState().isExpired())
    }
}

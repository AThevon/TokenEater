import Testing
import Foundation

@Suite("CodexTokenProvider")
struct CodexTokenProviderTests {

    @Test("credentials are read once and served from the cache afterwards")
    func caching() {
        let reader = MockCodexAuthReader()
        reader.stubbedCredentials = CodexFixtures.credentials()
        let sut = CodexTokenProvider(reader: reader)

        _ = sut.currentCredentials()
        _ = sut.currentCredentials()
        _ = sut.currentCredentials()

        #expect(reader.readCount == 1)
    }

    @Test("invalidating forces the next read to hit the file again")
    func invalidate() {
        let reader = MockCodexAuthReader()
        reader.stubbedCredentials = CodexFixtures.credentials()
        let sut = CodexTokenProvider(reader: reader)

        _ = sut.currentCredentials()
        sut.invalidate()
        _ = sut.currentCredentials()

        #expect(reader.readCount == 2)
    }

    @Test("a rotated token is reported as changed")
    func detectsRotation() {
        let reader = MockCodexAuthReader()
        reader.stubbedCredentials = CodexFixtures.credentials(accessToken: "token-a")
        let sut = CodexTokenProvider(reader: reader)
        _ = sut.currentCredentials()

        reader.stubbedCredentials = CodexFixtures.credentials(accessToken: "token-b")

        #expect(sut.refreshIfChanged())
        #expect(sut.currentCredentials()?.accessToken == "token-b")
    }

    @Test("an account swap is reported as changed even if the token string matched")
    func detectsAccountSwap() {
        let reader = MockCodexAuthReader()
        reader.stubbedCredentials = CodexFixtures.credentials(accessToken: "same", accountId: "acct-1")
        let sut = CodexTokenProvider(reader: reader)
        _ = sut.currentCredentials()

        reader.stubbedCredentials = CodexFixtures.credentials(accessToken: "same", accountId: "acct-2")

        #expect(sut.refreshIfChanged())
    }

    @Test("an unchanged token is not reported as a change")
    func stableTokenIsNotAChange() {
        let reader = MockCodexAuthReader()
        reader.stubbedCredentials = CodexFixtures.credentials(accessToken: "token-a")
        let sut = CodexTokenProvider(reader: reader)
        _ = sut.currentCredentials()

        #expect(!sut.refreshIfChanged())
    }

    @Test("the first population is not a change, so a fresh start does not look like a swap")
    func firstPopulationIsNotAChange() {
        let reader = MockCodexAuthReader()
        reader.stubbedCredentials = CodexFixtures.credentials()
        let sut = CodexTokenProvider(reader: reader)

        #expect(!sut.refreshIfChanged())
    }

    @Test("a transient read failure keeps the working token instead of dropping it")
    func transientFailureKeepsToken() {
        let reader = MockCodexAuthReader()
        reader.stubbedCredentials = CodexFixtures.credentials(accessToken: "token-a")
        let sut = CodexTokenProvider(reader: reader)
        _ = sut.currentCredentials()

        // The file is mid-write when we poll.
        reader.stubbedCredentials = nil

        #expect(!sut.refreshIfChanged())
        #expect(sut.currentCredentials()?.accessToken == "token-a")
    }
}

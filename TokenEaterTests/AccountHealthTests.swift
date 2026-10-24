import Testing
import Foundation

@Suite("AccountHealth")
struct AccountHealthTests {

    private let command = "CLAUDE_CONFIG_DIR=~/.claude-work claude"
    private let work = AccountID(rawValue: "acct-work")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func resolve(
        error: AppErrorState = .none,
        diagnostic: TokenDiagnostic = TokenDiagnostic(source: .keychainCLI, keychainFailure: nil),
        expiredSince: Date? = nil,
        identity: IdentityState = .unchecked,
        paused: Bool = false,
        lastUpdate: Date? = nil,
        folderExists: Bool = true
    ) -> AccountHealth {
        AccountHealth.resolve(
            errorState: error,
            diagnostic: diagnostic,
            loginExpiredSince: expiredSince,
            identityState: identity,
            isPaused: paused,
            lastUpdate: lastUpdate,
            folderExists: folderExists,
            command: command,
            names: [work: "Work", .main: "Perso"]
        )
    }

    @Test("a fresh account is checking, then up to date")
    func checkingThenUpToDate() {
        #expect(resolve() == .checking)
        #expect(resolve(lastUpdate: now) == .upToDate(now))
    }

    @Test("a paused account says so before anything else")
    func pauseFirst() {
        #expect(resolve(error: .tokenUnavailable, identity: .conflict(.belongsTo(.main)),
                        paused: true, lastUpdate: now, folderExists: false) == .paused(lastUpdate: now))
    }

    @Test("a folder that disappeared is reported as such")
    func folderMissing() {
        #expect(resolve(error: .tokenUnavailable, folderExists: false) == .folderMissing)
    }

    @Test("an identity conflict wins over an expired login, and names the other account")
    func conflictBeforeExpiry() {
        let health = resolve(
            error: .tokenUnavailable,
            diagnostic: TokenDiagnostic(source: .claudeDesktop, keychainFailure: nil),
            identity: .conflict(.belongsTo(work))
        )
        #expect(health == .identityConflict(.belongsTo(work), otherName: "Work", source: .claudeDesktop))
        let changed = resolve(identity: .conflict(.changed(newDigest: "d")))
        #expect(changed == .identityConflict(.changed(newDigest: "d"), otherName: nil, source: .keychainCLI))
    }

    @Test("a refused token with a source is an expired login, dated")
    func expired() {
        let since = now.addingTimeInterval(-7200)
        #expect(resolve(error: .tokenUnavailable, expiredSince: since) == .loginExpired(since: since, command: command))
        var diagnostic = TokenDiagnostic(source: .credentialsFile, keychainFailure: nil)
        diagnostic.tokenExpiresAt = since
        #expect(resolve(error: .tokenUnavailable, diagnostic: diagnostic) == .loginExpired(since: since, command: command))
    }

    @Test("no token at all is a missing login, or the Keychain's refusal when it refused")
    func noTokenCauses() {
        #expect(resolve(error: .tokenUnavailable, diagnostic: TokenDiagnostic(source: nil, keychainFailure: .notFound))
                == .noLogin(command: command))
        #expect(resolve(error: .tokenUnavailable, diagnostic: TokenDiagnostic(source: nil, keychainFailure: .accessDenied))
                == .accessDenied)
        #expect(resolve(error: .tokenUnavailable, diagnostic: TokenDiagnostic(source: nil, keychainFailure: .timedOut))
                == .timedOut)
    }

    @Test("a stale file token behind a refused Keychain read blames the Keychain")
    func staleFallback() {
        let diagnostic = TokenDiagnostic(source: .credentialsFile, keychainFailure: .accessDenied)
        #expect(resolve(error: .tokenUnavailable, diagnostic: diagnostic) == .accessDenied)
    }

    @Test("throttling and network failures are their own states")
    func transportStates() {
        #expect(resolve(error: .rateLimited, lastUpdate: now) == .rateLimited)
        #expect(resolve(error: .networkError, lastUpdate: now) == .network)
    }

    @Test("an identity check waiting on the profile is not an error")
    func pending() {
        let health = resolve(identity: .pending, lastUpdate: now)
        #expect(health == .identityPending)
        #expect(!health.needsAttention)
        #expect(AccountHealth.folderMissing.needsAttention)
    }
}

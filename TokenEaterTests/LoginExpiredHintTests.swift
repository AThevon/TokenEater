import Testing
import Foundation

@Suite("UsageStore login expired hint")
struct LoginExpiredHintTests {

    private let home = "/Users/test"
    private let service = "Claude Code-credentials-1a2b3c4d"

    @Test("the default chain keeps the plain claude hint")
    func defaultChainKeepsPlainHint() {
        #expect(UsageStore.renewCommand(scope: .defaultChain, home: home) == nil)
        #expect(UsageStore.loginExpiredHint(scope: .defaultChain, home: home)
                == String(localized: "error.login.expired.hint"))
    }

    @Test("a config folder names its own login command")
    func configDirNamesItsCommand() {
        let scope = CredentialScope.configDir(path: home + "/.claude-perso", service: service)
        #expect(UsageStore.renewCommand(scope: scope, home: home) == "CLAUDE_CONFIG_DIR=~/.claude-perso claude")
        #expect(UsageStore.loginExpiredHint(scope: scope, home: home)
                == String(format: String(localized: "error.login.expired.hint.dir"),
                          "CLAUDE_CONFIG_DIR=~/.claude-perso claude"))
    }

    @Test("~/.claude kept as a folder of its own still gets the variable")
    func explicitDefaultFolderGetsTheVariable() {
        let scope = CredentialScope.configDir(path: home + "/.claude", service: service)
        #expect(UsageStore.renewCommand(scope: scope, home: home) == "CLAUDE_CONFIG_DIR=~/.claude claude")
    }

    @Test("a folder that needs quoting goes through $HOME")
    func quotedFolderUsesHome() {
        let scope = CredentialScope.configDir(path: home + "/Claude Work", service: service)
        #expect(UsageStore.renewCommand(scope: scope, home: home) == "CLAUDE_CONFIG_DIR=\"$HOME/Claude Work\" claude")
    }
}

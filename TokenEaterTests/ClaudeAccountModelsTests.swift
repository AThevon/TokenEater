import Testing
import Foundation
import CryptoKit

@Suite("Claude account model")
struct ClaudeAccountModelsTests {

    private let home = "/Users/tester"

    private func sha8(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    // MARK: - AccountID

    @Test("an account id encodes as a bare string")
    func accountIDEncodesAsString() throws {
        let id = AccountID(rawValue: "acct-1234-abcd")
        let data = try JSONEncoder().encode([id])
        #expect(String(data: data, encoding: .utf8) == #"["acct-1234-abcd"]"#)
        #expect(try JSONDecoder().decode([AccountID].self, from: data) == [id])
    }

    @Test("the main account adds no storage suffix, an added one adds its id")
    func storageSuffix() {
        #expect(AccountID.main.storageSuffix.isEmpty)
        let extra = AccountID.makeExtra()
        #expect(extra.rawValue.hasPrefix("acct-"))
        #expect(extra.storageSuffix == "." + extra.rawValue)
        #expect(!extra.isMain)
        #expect(AccountID.isValid(extra.rawValue))
    }

    @Test("an id that could escape a key or a file name never decodes")
    func invalidIDsAreRefused() {
        for raw in ["", "main2", "acct-", "acct-../x", "acct-A", "acct-a/b", "work"] {
            let json = Data("[\"\(raw)\"]".utf8)
            #expect((try? JSONDecoder().decode([AccountID].self, from: json)) == nil, "\(raw)")
        }
    }

    // MARK: - Records

    @Test("a record decodes with only its id, every other field defaulted")
    func recordDecodesTolerantly() throws {
        let json = Data(#"{"id":"acct-1","name":42,"colorHex":"nope","isPaused":"yes"}"#.utf8)
        let record = try JSONDecoder().decode(ClaudeAccountRecord.self, from: json)
        #expect(record.id == AccountID(rawValue: "acct-1"))
        #expect(record.name == "Claude")
        #expect(record.colorHex == AccountPalette.presets[0])
        #expect(!record.isPaused)
        #expect(record.notificationsEnabled)
        #expect(record.configDir == nil)
        #expect(record.identityDigest == nil)
    }

    @Test("a record without an id fails, and the list drops only that entry")
    func recordWithoutIDIsDropped() {
        let json = Data(#"[{"name":"Lost"},{"id":"acct-2","configDir":"/Users/tester/.claude-work","name":"Work"}]"#.utf8)
        #expect((try? JSONDecoder().decode(ClaudeAccountRecord.self, from: Data(#"{"name":"Lost"}"#.utf8))) == nil)
        let records = ClaudeAccountsStorage.decode(json)
        #expect(records.map(\.id) == [.main, AccountID(rawValue: "acct-2")])
        #expect(records[1].name == "Work")
    }

    @Test("a record survives an encode / decode round trip")
    func recordRoundTrip() throws {
        let record = ClaudeAccountRecord(
            id: AccountID(rawValue: "acct-3"),
            configDir: "/Users/tester/.claude-work",
            service: "Claude Code-credentials-1a2b3c4d",
            name: "Work",
            colorHex: "#22D3EE",
            isPaused: true,
            notificationsEnabled: false,
            identityDigest: "abc",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try JSONDecoder().decode(ClaudeAccountRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
    }

    @Test("the main account can never be paused")
    func mainNeverPaused() throws {
        let record = ClaudeAccountRecord(id: .main, name: "Claude", colorHex: "#5B8DEF", isPaused: true)
        #expect(!record.isPaused)
        let json = Data(#"{"id":"main","isPaused":true}"#.utf8)
        #expect(try !JSONDecoder().decode(ClaudeAccountRecord.self, from: json).isPaused)
    }

    @Test("the stored list always starts with exactly one main account")
    func storageKeepsMainFirst() {
        #expect(ClaudeAccountsStorage.decode(nil).map(\.id) == [.main])
        let json = Data("""
        [{"id":"acct-1","configDir":"/a"},{"id":"main","name":"Perso"},
         {"id":"acct-1","configDir":"/b"},{"id":"acct-2","configDir":"/a"},
         {"id":"acct-3"}]
        """.utf8)
        let records = ClaudeAccountsStorage.decode(json)
        #expect(records.map(\.id.rawValue) == ["main", "acct-1"])
        #expect(records[0].name == "Perso")
    }

    @Test("an added account on ~/.claude is dropped while the main account reads it")
    func storageDropsSecondCopyOfDefaultFolder() {
        let json = Data("""
        [{"id":"main","name":"Perso"},
         {"id":"acct-1","configDir":"/Users/tester/.claude"},
         {"id":"acct-2","configDir":"/Users/tester/.claude-work/"}]
        """.utf8)
        let records = ClaudeAccountsStorage.decode(json, home: "/Users/tester")
        #expect(records.map(\.id.rawValue) == ["main", "acct-2"])

        // Once the main account lives elsewhere, ~/.claude is free.
        let moved = Data("""
        [{"id":"main","configDir":"/Users/tester/.claude-perso"},
         {"id":"acct-1","configDir":"/Users/tester/.claude"}]
        """.utf8)
        #expect(ClaudeAccountsStorage.decode(moved, home: "/Users/tester").map(\.id.rawValue) == ["main", "acct-1"])
    }

    @Test("the first three colours an account gets are far apart on the wheel")
    func paletteFirstChoicesAreDistinct() throws {
        var used: [String] = []
        for _ in 0..<3 { used.append(AccountPalette.nextColor(excluding: used)) }
        let hues = try used.map { try #require(AccountPalette.hue(of: $0)) }
        for i in 0..<hues.count {
            for j in (i + 1)..<hues.count {
                #expect(AccountPalette.hueDistance(hues[i], hues[j]) >= 30, "\(used[i]) vs \(used[j])")
            }
        }
        #expect(abs((AccountPalette.hue(of: "#5B8DEF") ?? 0) - 219.7) < 1)
    }

    @Test("a record's scope is the default chain without a folder, the folder's service with one")
    func recordScope() {
        #expect(ClaudeAccountRecord.defaultMain().scope == .defaultChain)
        let withService = ClaudeAccountRecord(id: .main, configDir: "/x", service: "S", name: "A", colorHex: "#5B8DEF")
        #expect(withService.scope == .configDir(path: "/x", service: "S"))
        let withoutService = ClaudeAccountRecord(id: .main, configDir: "/x", name: "A", colorHex: "#5B8DEF")
        #expect(withoutService.scope == .configDir(path: "/x", service: ClaudeConfigDirResolver.service(forHashInput: "/x")))
    }

    @Test("a scope locates its credentials, transcripts and session registry")
    func scopePaths() {
        let main = CredentialScope.defaultChain
        #expect(main.credentialsFilePath(home: home) == "/Users/tester/.claude/.credentials.json")
        #expect(main.projectsURL(home: home).path == "/Users/tester/.claude/projects")
        #expect(main.sessionsURL(home: home).path == "/Users/tester/.claude/sessions")
        #expect(main.includesClaudeDesktop)
        #expect(main.keychainService == "Claude Code-credentials")

        let custom = CredentialScope.configDir(path: "/Volumes/Work/claude", service: "S")
        #expect(custom.credentialsFilePath(home: home) == "/Volumes/Work/claude/.credentials.json")
        #expect(custom.projectsURL(home: home).path == "/Volumes/Work/claude/projects")
        #expect(custom.sessionsURL(home: home).path == "/Volumes/Work/claude/sessions")
        #expect(!custom.includesClaudeDesktop)
        #expect(custom.keychainService == "S")
    }

    // MARK: - Names and colours

    @Test("names are trimmed, cut at twelve characters and never empty")
    func nameSanitizing() {
        #expect(AccountNameRules.sanitize("  Work  ") == "Work")
        #expect(AccountNameRules.sanitize("A very long account name") == "A very long")
        #expect(AccountNameRules.sanitize("   ") == "Claude")
        #expect(AccountNameRules.sanitize("two\nlines") == "two lines")
        #expect(AccountNameRules.sanitize("Exactly12chr").count == 12)
    }

    @Test("the menu bar keeps eight characters, then an ellipsis")
    func menuBarLabel() {
        #expect(AccountNameRules.menuBarLabel("Personnelle") == "Personne…")
        #expect(AccountNameRules.menuBarLabel("Perso") == "Perso")
        #expect(AccountNameRules.menuBarLabel("Exactly8") == "Exactly8")
    }

    @Test("the next colour is the first preset nobody uses, cycling when all are taken")
    func paletteNextColor() {
        #expect(AccountPalette.nextColor(excluding: []) == "#5B8DEF")
        #expect(AccountPalette.nextColor(excluding: ["#5b8def"]) == "#F472B6")
        #expect(AccountPalette.nextColor(excluding: AccountPalette.presets) == AccountPalette.presets[0])
        #expect(AccountPalette.normalizedHex("22d3ee") == "#22D3EE")
        #expect(AccountPalette.normalizedHex("#12345") == nil)
    }

    @Test("no preset is a risk colour")
    func presetsAvoidRiskHues() {
        #expect(AccountPalette.presets.count == 8)
        #expect(Set(AccountPalette.presets).count == 8)
        for hex in AccountPalette.presets {
            #expect(AccountPalette.normalizedHex(hex) == hex)
        }
    }

    @Test("a mode choice carries an account only for Claude")
    func modeChoice() {
        #expect(ModeChoice(mode: .all).account == nil)
        #expect(ModeChoice(mode: .codex, account: AccountID(rawValue: "acct-1")).account == nil)
        #expect(ModeChoice(mode: .claude).account == .main)
        #expect(ModeChoice(mode: .claude).id == "claude")
        #expect(ModeChoice(mode: .claude, account: AccountID(rawValue: "acct-1")).id == "claude.acct-1")
    }

    // MARK: - Config dir resolver

    @Test("the service is the base name plus eight hex digits of the path's sha256")
    func serviceHash() {
        let path = "/Users/x/.claude-work"
        #expect(ClaudeConfigDirResolver.service(forHashInput: path) == "Claude Code-credentials-" + sha8(path))
        #expect(ClaudeConfigDirResolver.service(forHashInput: path).count == "Claude Code-credentials-".count + 8)
    }

    @Test("service candidates come in order and without duplicates")
    func serviceCandidates() {
        let candidates = ClaudeConfigDirResolver.serviceCandidates(for: "~/.claude-work/", home: home)
        let normalized = "/Users/tester/.claude-work"
        #expect(Array(candidates.prefix(3)) == [
            ClaudeConfigDirResolver.service(forHashInput: normalized),
            ClaudeConfigDirResolver.service(forHashInput: normalized + "/"),
            ClaudeConfigDirResolver.service(forHashInput: "~/.claude-work"),
        ])
        #expect(Set(candidates).count == candidates.count)
        // The symlink-resolved spelling of a path that does not exist is the
        // path itself, already listed.
        #expect(candidates.count == 3)
    }

    @Test("the default folder leads with the base service, then its suffixed spellings")
    func defaultFolderService() {
        let candidates = ClaudeConfigDirResolver.serviceCandidates(for: "/Users/tester/.claude", home: home)
        #expect(candidates.first == "Claude Code-credentials")
        // `CLAUDE_CONFIG_DIR=~/.claude` set explicitly still suffixes the service.
        #expect(candidates.dropFirst().first == ClaudeConfigDirResolver.service(forHashInput: "/Users/tester/.claude"))
        #expect(candidates.contains(ClaudeConfigDirResolver.service(forHashInput: "~/.claude")))
        #expect(Set(candidates).count == candidates.count)
        #expect(ClaudeConfigDirResolver.serviceCandidates(for: "~/.claude/", home: home) == candidates)
        #expect(ClaudeConfigDirResolver.isDefault("~/.claude", home: home))
        #expect(!ClaudeConfigDirResolver.isDefault("~/.claude-work", home: home))
    }

    @Test("normalize expands ~, folds dots, drops the trailing slash and composes Unicode")
    func normalize() {
        #expect(ClaudeConfigDirResolver.normalize("~/.claude-work/", home: home) == "/Users/tester/.claude-work")
        #expect(ClaudeConfigDirResolver.normalize("~", home: home) == "/Users/tester")
        #expect(ClaudeConfigDirResolver.normalize("/a/./b/../c//", home: home) == "/a/c")
        #expect(ClaudeConfigDirResolver.normalize(".claude-x", home: home) == "/Users/tester/.claude-x")
        let decomposed = "/Users/tester/.claude-e\u{0301}t\u{0065}\u{0301}"
        let composed = "/Users/tester/.claude-\u{00E9}t\u{00E9}"
        #expect(ClaudeConfigDirResolver.normalize(decomposed, home: home) == composed)
        #expect(Array(ClaudeConfigDirResolver.normalize(decomposed, home: home).unicodeScalars)
                == Array(composed.unicodeScalars))
    }

    @Test("a name is proposed from the folder, unique and within the limit")
    func proposedNames() {
        #expect(ClaudeConfigDirResolver.proposedName(forConfigDir: "/Users/x/.claude-work", existing: []) == "Work")
        #expect(ClaudeConfigDirResolver.proposedName(forConfigDir: "/Users/x/.claude", existing: []) == "Claude")
        #expect(ClaudeConfigDirResolver.proposedName(forConfigDir: "/Users/x/.claude-perso2", existing: []) == "Perso2")
        #expect(ClaudeConfigDirResolver.proposedName(forConfigDir: "/Users/x/.claude-work", existing: ["work"]) == "Work 2")
        #expect(ClaudeConfigDirResolver.proposedName(forConfigDir: "/Users/x/.claude-work", existing: ["Work", "Work 2"]) == "Work 3")
        let long = ClaudeConfigDirResolver.proposedName(forConfigDir: "/Users/x/.claude-abcdefghijklmnopqrst", existing: [])
        #expect(long == "Abcdefghijkl")
        #expect(long.count == 12)
        let longDuplicate = ClaudeConfigDirResolver.proposedName(forConfigDir: "/Users/x/.claude-abcdefghijklmnopqrst", existing: [long])
        #expect(longDuplicate == "Abcdefghij 2")
        #expect(ClaudeConfigDirResolver.proposedName(forConfigDir: "/Volumes/Data/company", existing: []) == "Company")
    }

    @Test("an email is masked to its first character and its domain")
    func maskEmail() {
        #expect(ClaudeConfigDirResolver.maskEmail("maya@acme.com") == "m•••@acme.com")
        #expect(ClaudeConfigDirResolver.maskEmail("  Z@x.io ") == "Z•••@x.io")
        #expect(ClaudeConfigDirResolver.maskEmail("noatsign") == "n•••")
        #expect(ClaudeConfigDirResolver.maskEmail("@acme.com") == "@•••")
        #expect(ClaudeConfigDirResolver.maskEmail("") == nil)
    }

    @Test("the identity digest is stable and carries no uuid in clear")
    func identityDigest() {
        let account = "8a3c1f2e-0000-4000-8000-123456789abc"
        let org = "11112222-3333-4444-5555-666677778888"
        let digest = ClaudeConfigDirResolver.identityDigest(accountUUID: account, organizationUUID: org)
        #expect(digest == ClaudeConfigDirResolver.identityDigest(accountUUID: account.uppercased(), organizationUUID: org))
        #expect(digest.count == 64)
        #expect(!digest.contains(account) && !digest.contains(org))
        #expect(digest != ClaudeConfigDirResolver.identityDigest(accountUUID: account, organizationUUID: nil))
    }

    @Test("paths show in their ~ form and the login command copies as is")
    func displayPathAndCommand() {
        #expect(ClaudeConfigDirResolver.displayPath("/Users/tester/.claude-work", home: home) == "~/.claude-work")
        #expect(ClaudeConfigDirResolver.displayPath("/Volumes/Work/claude", home: home) == "/Volumes/Work/claude")
        #expect(ClaudeConfigDirResolver.displayPath("/Users/testerbis/.claude", home: home) == "/Users/testerbis/.claude")
        #expect(ClaudeConfigDirResolver.loginCommand(forConfigDir: "/Users/tester/.claude-work", home: home)
                == "CLAUDE_CONFIG_DIR=~/.claude-work claude")
        #expect(ClaudeConfigDirResolver.loginCommand(forConfigDir: "/Users/tester/My Claude", home: home)
                == #"CLAUDE_CONFIG_DIR="$HOME/My Claude" claude"#)
        #expect(ClaudeConfigDirResolver.serviceSuffix("Claude Code-credentials-1a2b3c4d") == "-1a2b3c4d")
        #expect(ClaudeConfigDirResolver.serviceSuffix("Claude Code-credentials") == "")
    }
}

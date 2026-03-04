import Testing

@Suite("ProcessResolver")
struct ProcessResolverTests {

    // MARK: - npm install

    @Test("detects npm-installed Claude")
    func detectsNpmInstall() {
        let path = "/Users/simon/.local/share/claude/versions/1.0.0/node"
        #expect(ProcessResolver.isClaudePath(path))
    }

    // MARK: - Homebrew Cask

    @Test("detects Homebrew Cask Claude (arm64)")
    func detectsHomebrewCaskArm64() {
        let path = "/opt/homebrew/Caskroom/claude-code/2.1.63/claude"
        #expect(ProcessResolver.isClaudePath(path))
    }

    @Test("detects Homebrew Cask Claude (x86_64)")
    func detectsHomebrewCaskX86() {
        let path = "/usr/local/Caskroom/claude-code/2.1.63/claude"
        #expect(ProcessResolver.isClaudePath(path))
    }

    // MARK: - Non-Claude paths

    @Test("rejects unrelated process")
    func rejectsUnrelated() {
        let path = "/usr/bin/python3"
        #expect(!ProcessResolver.isClaudePath(path))
    }

    @Test("rejects empty path")
    func rejectsEmpty() {
        #expect(!ProcessResolver.isClaudePath(""))
    }
}

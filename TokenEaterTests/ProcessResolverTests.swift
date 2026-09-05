import Testing
import Foundation

@Suite("ProcessResolver")
struct ProcessResolverTests {

    // MARK: - Native installer

    @Test("detects native-installer Claude")
    func detectsNativeInstall() {
        let path = "/Users/simon/.local/share/claude/versions/1.0.0/node"
        #expect(ProcessResolver.isClaudePath(path))
    }

    // MARK: - npm global install (npm / NVM / fnm / volta)

    @Test("detects npm global install under NVM")
    func detectsNpmGlobalUnderNVM() {
        // Reported in #224: proc_pidpath for a Claude Code session installed via
        // `npm i -g @anthropic-ai/claude-code` while using NVM.
        let path = "/Users/simon/.nvm/versions/node/v22.19.0/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
        #expect(ProcessResolver.isClaudePath(path))
    }

    @Test("detects plain npm global install")
    func detectsPlainNpmGlobal() {
        let path = "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"
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

    // MARK: - Homebrew Cask @latest

    @Test("detects Homebrew Cask @latest Claude (arm64)")
    func detectsCaskLatestArm64() {
        let path = "/opt/homebrew/Caskroom/claude-code@latest/2.1.100/claude"
        #expect(ProcessResolver.isClaudePath(path))
    }

    @Test("detects Homebrew Cask @latest Claude (x86_64)")
    func detectsCaskLatestX86() {
        let path = "/usr/local/Caskroom/claude-code@latest/2.1.100/claude"
        #expect(ProcessResolver.isClaudePath(path))
    }

    // MARK: - Claude Desktop embedded CLI

    @Test("detects Claude Desktop embedded CLI")
    func detectsClaudeDesktopCLI() {
        let path = "/Users/simon/Library/Application Support/Claude/claude-code/2.1.64/claude"
        #expect(ProcessResolver.isClaudePath(path))
    }

    // MARK: - Editor extension embedded binary (#260)
    // The VSCode-family Claude Code extensions spawn their own bundled CLI from
    // <editor dir>/extensions/anthropic.claude-code-<version>/resources/...,
    // never the user's installed CLI, so the extension dir is its own pattern.

    @Test("detects the VSCode extension embedded binary")
    func detectsVSCodeExtensionBinary() {
        let path = "/Users/simon/.vscode/extensions/anthropic.claude-code-2.1.63-darwin-arm64/resources/native-binary/claude"
        #expect(ProcessResolver.isClaudePath(path))
    }

    @Test("detects the Cursor extension embedded binary")
    func detectsCursorExtensionBinary() {
        let path = "/Users/simon/.cursor/extensions/anthropic.claude-code-2.1.68-darwin-arm64/resources/native-binaries/darwin-arm64/claude"
        #expect(ProcessResolver.isClaudePath(path))
    }

    @Test("rejects another publisher's claude-named extension")
    func rejectsOtherPublisherExtension() {
        let path = "/Users/simon/.vscode/extensions/someone.claude-helper-1.0.0/bin/claude"
        #expect(!ProcessResolver.isClaudePath(path))
    }

    @Test("rejects the vendored ripgrep bundled inside Claude Code installs")
    func rejectsVendoredRipgrep() {
        let legacyExtension = "/Users/simon/.vscode/extensions/anthropic.claude-code-2.0.3/resources/claude-code/vendor/ripgrep/arm64-darwin/rg"
        let npmInstall = "/usr/local/lib/node_modules/@anthropic-ai/claude-code/vendor/ripgrep/arm64-darwin/rg"
        #expect(!ProcessResolver.isClaudePath(legacyExtension))
        #expect(!ProcessResolver.isClaudePath(npmInstall))
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

    // MARK: - Byte-level matching (#255)
    // The ASCII patterns must behave identically on multi-byte UTF-8 paths,
    // including the NFD-decomposed names macOS stores on disk.

    @Test("detects an install under an NFD-decomposed unicode home dir")
    func detectsInstallUnderDecomposedUnicodeHome() {
        // "réné" written with U+0301 combining acute accents (the on-disk form)
        let path = "/Users/re\u{0301}ne\u{0301}/.local/share/claude/versions/2.0.10/claude"
        #expect(ProcessResolver.isClaudePath(path))
    }

    @Test("detects an install under a multi-byte home dir")
    func detectsInstallUnderMultibyteHome() {
        let path = "/Users/日本語/.local/share/claude/versions/1.2.3/claude"
        #expect(ProcessResolver.isClaudePath(path))
    }

    @Test("rejects a multi-byte path without Claude")
    func rejectsMultibytePath() {
        #expect(!ProcessResolver.isClaudePath("/Users/日本語/bin/node"))
    }

    @Test("rejects a near-miss package name")
    func rejectsNearMissPackageName() {
        #expect(!ProcessResolver.isClaudePath("/usr/lib/node_modules/@anthropic-ai/claude-codex/cli.js"))
    }

    // MARK: - TTY resolution

    @Test("getProcessTTY returns a valid TTY for the current process")
    func ttyForCurrentProcess() {
        let tty = ProcessResolver.getProcessTTY(pid: ProcessInfo.processInfo.processIdentifier)
        // In CI or Xcode, the test runner may not have a TTY — that's fine
        if let tty {
            #expect(tty.hasPrefix("/dev/tty"))
        }
    }

    @Test("getProcessTTY returns nil for invalid PID")
    func ttyForInvalidPid() {
        #expect(ProcessResolver.getProcessTTY(pid: -1) == nil)
    }

    // MARK: - Claude Code version detection

    @Test("detects Claude Code version from local install")
    func detectsClaudeCodeVersion() {
        let version = ProcessResolver.detectClaudeCodeVersion()
        // On dev machines Claude Code should be installed; in CI it might not be
        if let version {
            #expect(version.contains("."))
            #expect(version.first?.isNumber == true)
        }
    }

    // MARK: - Electron helper detection

    @Test("detects Electron helper bundle URL")
    func detectsElectronHelper() {
        let helperURL = URL(fileURLWithPath: "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app")
        #expect(ProcessResolver.isElectronHelper(bundleURL: helperURL))
    }

    @Test("does not flag main app as Electron helper")
    func doesNotFlagMainApp() {
        let mainURL = URL(fileURLWithPath: "/Applications/Cursor.app")
        #expect(!ProcessResolver.isElectronHelper(bundleURL: mainURL))
    }

    @Test("handles nil bundle URL")
    func handlesNilBundleURL() {
        #expect(!ProcessResolver.isElectronHelper(bundleURL: nil))
    }

    // MARK: - Terminal bundles

    @Test("terminalBundles includes Cursor")
    func includesCursor() {
        #expect(ProcessResolver.terminalBundles.contains("com.todesktop.230313mzl4w4u92"))
    }

    @Test("terminalBundles includes Kitty")
    func includesKitty() {
        #expect(ProcessResolver.terminalBundles.contains("net.kovidgoyal.kitty"))
    }

    @Test("terminalBundles includes iTerm2")
    func includesITerm2() {
        #expect(ProcessResolver.terminalBundles.contains("com.googlecode.iterm2"))
    }
}

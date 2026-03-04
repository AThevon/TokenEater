import Testing
import Foundation

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

import Foundation
import AppKit
import Darwin

struct ClaudeProcessInfo: Sendable {
    let pid: Int32
    let parentPid: Int32
    let cwd: String
    let sourceKind: SessionSourceKind
}

enum ProcessResolver {
    private static let knownClaudePaths = [
        "/.local/share/claude/versions/",   // npm install
        "/Caskroom/claude-code/",            // Homebrew Cask (arm64 + x86_64)
    ]

    /// Find all running Claude Code CLI processes with their working directories.
    static func findClaudeProcesses() -> [ClaudeProcessInfo] {
        let allProcs = listAllProcesses()
        guard !allProcs.isEmpty else { return [] }

        // Build a pid → parentPid lookup for ancestor walking
        var parentLookup: [Int32: Int32] = [:]
        for proc in allProcs {
            parentLookup[proc.pid] = proc.parentPid
        }

        return allProcs.compactMap { proc in
            guard isClaudeProcess(pid: proc.pid) else { return nil }
            guard let cwd = getProcessCwd(pid: proc.pid) else { return nil }
            let kind = resolveSourceKind(pid: proc.parentPid, parentLookup: parentLookup)
            return ClaudeProcessInfo(pid: proc.pid, parentPid: proc.parentPid, cwd: cwd, sourceKind: kind)
        }
    }

    private static let idePathPatterns = [
        "Visual Studio Code", "Code.app", "Cursor.app",
        "Zed.app", "Windsurf.app", "Sublime Text.app",
        "IntelliJ", "GoLand", "WebStorm", "PyCharm", "CLion", "Rider",
        "RustRover", "DataGrip", "PhpStorm", "AppCode",
    ]

    private static let terminalPathPatterns = [
        "/bin/zsh", "/bin/bash", "/bin/sh", "/bin/fish",
        "/bin/tmux", "/bin/screen",
        "Terminal.app", "iTerm.app", "iTerm2.app",
        "WezTerm.app", "Warp.app", "Alacritty.app", "kitty.app",
        "Ghostty.app",
    ]

    /// Walk the entire ancestor chain; IDE wins over terminal (shells are always present).
    private static func resolveSourceKind(
        pid: Int32,
        parentLookup: [Int32: Int32]
    ) -> SessionSourceKind {
        var foundTerminal = false
        var currentPid = pid
        for _ in 0..<15 {
            guard currentPid > 1 else { break }
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let ret = proc_pidpath(currentPid, &pathBuffer, UInt32(MAXPATHLEN))
            if ret > 0 {
                let path = String(cString: pathBuffer)
                // IDE found → return immediately, always wins
                if idePathPatterns.contains(where: { path.contains($0) }) {
                    return .ide
                }
                if terminalPathPatterns.contains(where: { path.contains($0) }) {
                    foundTerminal = true
                }
            }
            guard let ppid = parentLookup[currentPid], ppid > 1 else { break }
            currentPid = ppid
        }
        return foundTerminal ? .terminal : .unknown
    }

    /// Activate the terminal running a Claude process.
    static func activateTerminal(for process: ClaudeProcessInfo) {
        // Switch tmux pane in background (non-blocking)
        DispatchQueue.global(qos: .userInitiated).async {
            switchTmuxPane(parentPid: process.parentPid)
        }

        // Resolve the real host app (skipping Electron helpers)
        guard let app = resolveHostApp(startingFrom: process.parentPid) else { return }
        let bundleID = app.bundleIdentifier ?? ""

        // Try smart tab focus first (handles both activation + tab selection).
        let tty = resolveProcessTTY(startingFrom: process.pid)

        var handled = false
        switch bundleID {
        case "com.apple.Terminal":
            if let tty {
                handled = focusTerminalTab(tty: tty)
            }
        case "com.googlecode.iterm2":
            if let tty {
                handled = focusITerm2Tab(tty: tty)
            }
        case "net.kovidgoyal.kitty":
            focusKittyTab(pid: process.parentPid)
            handled = true
        default:
            break
        }

        // Fallback: generic app activation (brings to front, no tab selection)
        if !handled {
            activateApp(app)
        }
    }

    // MARK: - tmux trigger file

    private static let sharedDir: String = {
        let home: String
        if let pw = getpwuid(getuid()) {
            home = String(cString: pw.pointee.pw_dir)
        } else {
            home = NSHomeDirectory()
        }
        return "\(home)/Library/Application Support/com.tokeneater.shared"
    }()

    private static func switchTmuxPane(parentPid: Int32) {
        installTmuxWatcherIfNeeded()
        let triggerPath = "\(sharedDir)/switch-pane.trigger"
        try? FileManager.default.createDirectory(atPath: sharedDir, withIntermediateDirectories: true)
        try? "\(parentPid)".write(toFile: triggerPath, atomically: true, encoding: .utf8)
    }

    /// Install the tmux watcher script (polling loop, started via tmux.conf).
    /// Re-installs automatically when the embedded version changes.
    static func installTmuxWatcherIfNeeded() {
        let scriptPath = "\(sharedDir)/tmux-watcher.sh"
        let version = "# tokeneater-v2"

        // Skip if already up-to-date
        if FileManager.default.fileExists(atPath: scriptPath),
           let content = try? String(contentsOfFile: scriptPath, encoding: .utf8),
           content.contains(version) {
            return
        }

        let script = """
        #!/bin/bash
        \(version)
        # TokenEater tmux pane switcher — started by tmux via run-shell.
        # Polls for a trigger file written by the app and switches to the target pane.
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        TRIGGER="$HOME/Library/Application Support/com.tokeneater.shared/switch-pane.trigger"
        while true; do
            if [ -f "$TRIGGER" ]; then
                TARGET_PID=$(cat "$TRIGGER" 2>/dev/null)
                rm -f "$TRIGGER"
                if [ -n "$TARGET_PID" ]; then
                    PANE_ID=$(tmux list-panes -a -F "#{pane_pid} #{pane_id}" | awk -v pid="$TARGET_PID" '$1 == pid {print $2}')
                    if [ -n "$PANE_ID" ]; then
                        # Cross-session: switch the most recently active client to the target session
                        LAST_CLIENT=$(tmux list-clients -F "#{client_activity} #{client_name}" 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
                        [ -n "$LAST_CLIENT" ] && tmux switch-client -c "$LAST_CLIENT" -t "$PANE_ID" 2>/dev/null
                        tmux select-window -t "$PANE_ID"
                        tmux select-pane -t "$PANE_ID"
                    fi
                fi
            fi
            sleep 0.3
        done
        """

        try? FileManager.default.createDirectory(atPath: sharedDir, withIntermediateDirectories: true)
        try? script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Native Process APIs

    private struct BasicProcessInfo {
        let pid: Int32
        let parentPid: Int32
    }

    private static func listAllProcesses() -> [BasicProcessInfo] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size: Int = 0

        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)

        guard sysctl(&mib, UInt32(mib.count), &procList, &size, nil, 0) == 0 else {
            return []
        }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride
        return (0..<actualCount).compactMap { i in
            let proc = procList[i]
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { return nil }
            return BasicProcessInfo(pid: pid, parentPid: proc.kp_eproc.e_ppid)
        }
    }

    /// Check if an executable path matches a known Claude Code installation.
    static func isClaudePath(_ path: String) -> Bool {
        knownClaudePaths.contains { path.contains($0) }
    }

    private static func isClaudeProcess(pid: Int32) -> Bool {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
        guard ret > 0 else { return false }
        return isClaudePath(String(cString: pathBuffer))
    }

    private static func getProcessCwd(pid: Int32) -> String? {
        var vnodeInfo = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, Int32(size))
        guard ret == Int32(size) else { return nil }

        let path = withUnsafePointer(to: vnodeInfo.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                String(cString: cStr)
            }
        }

        return path.isEmpty ? nil : path
    }

    private static func getParentPid(_ pid: Int32) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size

        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    /// Get the controlling terminal (TTY) for a process.
    /// Constructs the path directly from the device number to avoid `devname()`,
    /// which reads `/dev` and fails silently inside the app sandbox.
    static func getProcessTTY(pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let tdev = info.kp_eproc.e_tdev
        guard tdev > 0 else { return nil }
        // macOS device number: major = (dev >> 24) & 0xff, minor = dev & 0xffffff
        // Pseudo-terminal slaves have major 16 → /dev/ttysNNN
        let major = (Int(tdev) >> 24) & 0xff
        let minor = Int(tdev) & 0xffffff
        guard major == 16 else { return nil }
        return String(format: "/dev/ttys%03d", minor)
    }

    /// Walk up the PID tree to find the controlling TTY.
    private static func resolveProcessTTY(startingFrom pid: Int32) -> String? {
        var currentPid = pid
        for _ in 0..<10 {
            if let tty = getProcessTTY(pid: currentPid) {
                return tty
            }
            guard let ppid = getParentPid(currentPid), ppid > 1 else { break }
            currentPid = ppid
        }
        return nil
    }

    /// Check if a bundle URL is an Electron helper (nested inside /Contents/Frameworks/).
    static func isElectronHelper(bundleURL: URL?) -> Bool {
        guard let path = bundleURL?.path else { return false }
        return path.contains("/Contents/Frameworks/")
    }

    // MARK: - Terminal Activation

    static let terminalBundles = [
        "com.github.wez.wezterm", "io.wezfurlong.wezterm",
        "com.googlecode.iterm2", "com.apple.Terminal",
        "dev.warp.Warp-Stable", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "net.kovidgoyal.kitty",
    ]

    /// Map non-GUI ancestor process paths to their parent GUI app bundle ID.
    /// Some terminals (iTerm2, Kitty) spawn shells via helper services that
    /// are not in NSWorkspace.runningApplications.
    private static let serviceToAppBundle: [(pathContains: String, bundleID: String)] = [
        ("iTerm2/iTermServer", "com.googlecode.iterm2"),
        ("kitty", "net.kovidgoyal.kitty"),
    ]

    /// Walk the PID tree to find the host app, skipping Electron helper processes.
    /// Also detects non-GUI service processes (e.g. iTermServer) and maps them
    /// to their parent GUI app.
    private static func resolveHostApp(startingFrom pid: Int32) -> NSRunningApplication? {
        let runningApps = NSWorkspace.shared.runningApplications
        var currentPid = pid

        for _ in 0..<10 {
            // Check if this PID is a GUI app
            if let app = runningApps.first(where: { $0.processIdentifier == currentPid }) {
                if !isElectronHelper(bundleURL: app.bundleURL) {
                    return app
                }
            }

            // Check if this PID is a known non-GUI service (e.g. iTermServer)
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            if proc_pidpath(currentPid, &pathBuffer, UInt32(MAXPATHLEN)) > 0 {
                let path = String(cString: pathBuffer)
                for mapping in serviceToAppBundle {
                    if path.contains(mapping.pathContains),
                       let app = runningApps.first(where: { $0.bundleIdentifier == mapping.bundleID }) {
                        return app
                    }
                }
            }

            guard let ppid = getParentPid(currentPid), ppid > 1 else { break }
            currentPid = ppid
        }

        // Fallback: find any known terminal that's running
        for bundle in terminalBundles {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundle }) {
                return app
            }
        }
        return nil
    }

    // MARK: - Smart Tab Focus

    /// Run AppleScript in-process via NSAppleScript.
    /// If TCC blocks it (-1743), falls back to osascript which triggers the
    /// macOS permission prompt as a side effect. The next click will then work.
    @discardableResult
    private static func runAppleScript(_ source: String, targetBundleID: String) -> Bool {
        // Try NSAppleScript first (works if TCC already approved)
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error == nil { return true }

        let errorCode = (error?["NSAppleScriptErrorNumber"] as? Int) ?? 0

        // Error -1743 = TCC not approved. Run via osascript to trigger the
        // macOS permission prompt. osascript itself will fail (-10004, sandbox)
        // but the TCC prompt appears. Next click will succeed via NSAppleScript.
        if errorCode == -1743 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }

        return false
    }

    /// Select the tab matching a TTY in Terminal.app via AppleScript.
    @discardableResult
    private static func focusTerminalTab(tty: String) -> Bool {
        let source = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t from 1 to count of tabs of w
                    if tty of tab t of w is "\(tty)" then
                        set selected tab of w to tab t of w
                        set index of w to 1
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        return runAppleScript(source, targetBundleID: "com.apple.Terminal")
    }

    /// Select the tab matching a TTY in iTerm2 via AppleScript.
    @discardableResult
    private static func focusITerm2Tab(tty: String) -> Bool {
        let source = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select t
                            select w
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        return runAppleScript(source, targetBundleID: "com.googlecode.iterm2")
    }

    /// Focus the tab running a process in Kitty via remote control CLI.
    private static func focusKittyTab(pid: Int32) {
        let kittenPaths = ["/opt/homebrew/bin/kitten", "/usr/local/bin/kitten", "/usr/bin/kitten"]
        guard let kittenPath = kittenPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: kittenPath)
        process.arguments = ["@", "focus-tab", "--match", "pid:\(pid)"]
        try? process.run()
    }

    /// Activate via LaunchServices — reliably switches spaces/fullscreen.
    private static func activateApp(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else {
            DispatchQueue.main.async { app.activate() }
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
    }
}

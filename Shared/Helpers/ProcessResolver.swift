import Foundation
import AppKit
import Darwin

struct ClaudeProcessInfo: Sendable {
    let pid: Int32
    let parentPid: Int32
    let cwd: String
}

enum ProcessResolver {
    private static let claudeVersionsPath = "/.local/share/claude/versions/"

    /// Find all running Claude Code CLI processes with their working directories.
    static func findClaudeProcesses() -> [ClaudeProcessInfo] {
        let allProcs = listAllProcesses()
        guard !allProcs.isEmpty else { return [] }

        return allProcs.compactMap { proc in
            guard isClaudeProcess(pid: proc.pid) else { return nil }
            guard let cwd = getProcessCwd(pid: proc.pid) else { return nil }
            return ClaudeProcessInfo(pid: proc.pid, parentPid: proc.parentPid, cwd: cwd)
        }
    }

    /// Activate the terminal running a Claude process.
    static func activateTerminal(for process: ClaudeProcessInfo) {
        // Switch tmux pane in background (non-blocking)
        DispatchQueue.global(qos: .userInitiated).async {
            switchTmuxPane(parentPid: process.parentPid)
        }
        // Activate terminal app immediately (don't wait for tmux)
        activateParentApp(pid: process.parentPid)
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
    static func installTmuxWatcherIfNeeded() {
        let scriptPath = "\(sharedDir)/tmux-watcher.sh"
        guard !FileManager.default.fileExists(atPath: scriptPath) else { return }

        let script = """
        #!/bin/bash
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
                    [ -n "$PANE_ID" ] && tmux select-window -t "$PANE_ID" && tmux select-pane -t "$PANE_ID"
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

    private static func isClaudeProcess(pid: Int32) -> Bool {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
        guard ret > 0 else { return false }
        let path = String(cString: pathBuffer)
        return path.contains(claudeVersionsPath)
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

    // MARK: - Terminal Activation

    private static func activateParentApp(pid: Int32) {
        let runningApps = NSWorkspace.shared.runningApplications
        var currentPid = pid

        for _ in 0..<10 {
            if let app = runningApps.first(where: { $0.processIdentifier == currentPid }) {
                activateApp(app)
                return
            }
            guard let ppid = getParentPid(currentPid), ppid > 1 else { break }
            currentPid = ppid
        }

        let terminalBundles = [
            "com.github.wez.wezterm", "io.wezfurlong.wezterm",
            "com.googlecode.iterm2", "com.apple.Terminal",
            "dev.warp.Warp-Stable", "com.microsoft.VSCode"
        ]
        for bundle in terminalBundles {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundle }) {
                activateApp(app)
                return
            }
        }
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

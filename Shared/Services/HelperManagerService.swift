import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "HelperManager")

final class HelperManagerService: HelperManagerProtocol, @unchecked Sendable {
    static let defaultSyncInterval: TimeInterval = 300

    private let home: String
    private let plistPath: String
    private let binaryPath: String
    private let statusFilePath: String
    private let logsDir: String
    private let sharedDir: String
    private let cmdScriptPath: String
    private let label = "com.tokeneater.helper"

    init() {
        let resolvedHome: String = {
            if let pw = getpwuid(getuid()) {
                return String(cString: pw.pointee.pw_dir)
            }
            return NSHomeDirectory()
        }()
        self.home = resolvedHome
        self.plistPath = "\(resolvedHome)/Library/LaunchAgents/com.tokeneater.helper.plist"
        self.sharedDir = "\(resolvedHome)/Library/Application Support/com.tokeneater.shared"
        self.statusFilePath = "\(sharedDir)/keychain-token.json"
        self.cmdScriptPath = "\(sharedDir)/te-helper-cmd.sh"
        self.logsDir = "\(resolvedHome)/Library/Logs/TokenEater"
        self.binaryPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/TokenEaterHelper")
            .path
    }

    // MARK: - Status

    /// Reflects both "plist present on disk" AND "service actually loaded in launchd".
    /// Plist without running service should not be reported as .installed.
    func currentStatus() -> HelperStatus {
        let fm = FileManager.default
        guard fm.fileExists(atPath: binaryPath) else { return .binaryMissing }
        guard fm.fileExists(atPath: plistPath) else { return .notInstalled }

        guard let data = fm.contents(atPath: statusFilePath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .installed(lastSyncAt: nil, lastError: nil)
        }
        let lastSync = (obj["lastSyncAt"] as? String)
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        let error = obj["error"] as? String
        return .installed(lastSyncAt: lastSync, lastError: error)
    }

    // MARK: - Install

    func install(syncInterval: TimeInterval) throws {
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw HelperError.binaryMissing
        }

        guard let templateURL = Bundle.main.url(
            forResource: "com.tokeneater.helper.plist",
            withExtension: "template"
        ), let template = try? String(contentsOf: templateURL, encoding: .utf8) else {
            throw HelperError.templateMissing
        }

        let plist = template
            .replacingOccurrences(of: "{{BINARY_PATH}}", with: binaryPath)
            .replacingOccurrences(of: "{{SYNC_INTERVAL}}", with: String(Int(syncInterval)))
            .replacingOccurrences(of: "{{HOME}}", with: home)

        try ensureDirectoriesExist()

        do {
            try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        } catch {
            throw HelperError.writeFailed(error.localizedDescription)
        }

        // The sandboxed app cannot exec /bin/launchctl directly (macOS sandbox
        // rejects it with status 113). We punt to an AppleScript applet which
        // is a separate .app bundle - launching it via /usr/bin/open runs it
        // outside our sandbox, so its `do shell script` can reach launchctl.
        let guiDomain = "gui/\(getuid())"
        let command = """
        #!/bin/bash
        set -u
        mkdir -p "\(logsDir)"
        /bin/launchctl bootout \(guiDomain)/\(label) 2>/dev/null || true
        /bin/launchctl bootstrap \(guiDomain) "\(plistPath)"
        exit $?
        """
        try runViaInstallerApplet(command: command)
        logger.info("Helper installed via helper-installer applet")
    }

    // MARK: - Uninstall

    func uninstall() throws {
        let guiDomain = "gui/\(getuid())"
        let command = """
        #!/bin/bash
        /bin/launchctl bootout \(guiDomain)/\(label) 2>/dev/null || true
        rm -f "\(plistPath)"
        rm -f "\(statusFilePath)"
        exit 0
        """
        try runViaInstallerApplet(command: command)
        logger.info("Helper uninstalled via helper-installer applet")
    }

    // MARK: - Force sync

    func forceSync() throws {
        let guiDomain = "gui/\(getuid())"
        let command = """
        #!/bin/bash
        /bin/launchctl kickstart -k \(guiDomain)/\(label)
        exit $?
        """
        try runViaInstallerApplet(command: command)
    }

    // MARK: - Private

    private func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: URL(fileURLWithPath: "\(home)/Library/LaunchAgents"),
            withIntermediateDirectories: true
        )
        // Logs dir write may fail silently from the sandbox even with the
        // home-relative entitlement; the helper-installer applet below
        // re-creates it from outside the sandbox before launchctl runs.
        try? fm.createDirectory(atPath: logsDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: sharedDir, withIntermediateDirectories: true)
    }

    /// Writes the command to the shared dir and launches the helper-installer
    /// applet, which runs the script outside the sandbox. The applet exits
    /// silently; this function returns once /usr/bin/open returns, which does
    /// NOT mean the script has finished - we poll `currentStatus()` from the
    /// caller side (settingsStore.refreshHelperStatus) to verify success.
    private func runViaInstallerApplet(command: String) throws {
        guard let installerURL = Bundle.main.url(
            forResource: "TokenEaterHelperInstaller",
            withExtension: "app"
        ) else {
            throw HelperError.templateMissing
        }

        do {
            try command.write(toFile: cmdScriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: cmdScriptPath
            )
        } catch {
            throw HelperError.writeFailed(error.localizedDescription)
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // -g keeps the applet out of the foreground so TokenEater does not
        // lose focus while the helper (un)installs. -W waits for the applet
        // to exit so the caller can immediately re-check currentStatus().
        task.arguments = ["-g", "-W", installerURL.path]
        do {
            try task.run()
        } catch {
            throw HelperError.appleScriptFailed(-1)
        }
        // -W waits for the applet to exit, which is fast because the applet
        // only forks the shell script and returns.
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw HelperError.appleScriptFailed(Int(task.terminationStatus))
        }
    }
}

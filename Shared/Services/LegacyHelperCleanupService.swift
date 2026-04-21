import Foundation
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "LegacyHelperCleanup")

/// One-shot cleanup for users upgrading from v4.x to v5.0+.
///
/// v5.0 desandboxes the main app and replaces the LaunchAgent helper (which
/// shelled out to `/usr/bin/security` from outside the sandbox) with direct
/// in-process shell-out via `SecurityCLIReader`. That means two things need to
/// happen on the first v5.0 launch for upgrading users:
///
/// 1. Import the user's UserDefaults from the v4.x sandbox container into the
///    now-real-path plist the desandboxed app reads. Without this, existing
///    users would see onboarding again and lose all their preferences.
/// 2. Unload + delete the `com.tokeneater.helper` LaunchAgent, its plist, and
///    the `keychain-token.json` it used to maintain. Leftover cruft otherwise.
///
/// Both steps are gated by a UserDefaults flag so they only run once, and both
/// are safe no-ops for fresh installs. Scheduled for removal in v5.1 once the
/// upgraded population has had time to go through at least one launch.
final class LegacyHelperCleanupService: @unchecked Sendable {
    private static let cleanupDoneKey = "legacyHelperCleanupDone"
    private static let prefsMigratedKey = "legacySandboxPrefsMigrated"

    private let label = "com.tokeneater.helper"
    private let bundleID = "com.tokeneater.app"

    private var home: String {
        if let pw = getpwuid(getuid()) {
            return String(cString: pw.pointee.pw_dir)
        }
        return NSHomeDirectory()
    }

    /// Migrate the v4.x sandbox-container UserDefaults into the real path so the
    /// desandboxed v5.0 app sees the user's existing prefs. Must run BEFORE any
    /// `UserDefaults.standard` read in the app - call this in `AppDelegate
    /// .applicationDidFinishLaunching` before stores are constructed.
    func migratePrefsIfNeeded() {
        if UserDefaults.standard.bool(forKey: Self.prefsMigratedKey) { return }

        let fm = FileManager.default
        let sandboxPlist = "\(home)/Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).plist"
        guard fm.fileExists(atPath: sandboxPlist) else {
            UserDefaults.standard.set(true, forKey: Self.prefsMigratedKey)
            return
        }

        guard let data = fm.contents(atPath: sandboxPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else {
            UserDefaults.standard.set(true, forKey: Self.prefsMigratedKey)
            return
        }

        // Copy every v4.x preference into the real UserDefaults. Keep anything
        // already in the real path (unlikely on a fresh upgrade) so we don't
        // overwrite v5.0 writes that happened before migration.
        let defaults = UserDefaults.standard
        var migratedCount = 0
        for (key, value) in dict {
            if defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
                migratedCount += 1
            }
        }
        defaults.set(true, forKey: Self.prefsMigratedKey)
        logger.info("Migrated \(migratedCount, privacy: .public) keys from sandbox plist")
    }

    /// Run the helper cleanup if it hasn't run yet. Safe to call on every launch -
    /// subsequent calls return immediately via the UserDefaults flag.
    func runIfNeeded() {
        if UserDefaults.standard.bool(forKey: Self.cleanupDoneKey) { return }

        let plistPath = "\(home)/Library/LaunchAgents/\(label).plist"
        let sharedDir = "\(home)/Library/Application Support/com.tokeneater.shared"
        let statusFile = "\(sharedDir)/keychain-token.json"

        // If no legacy artifact is present, nothing to do - flag the migration
        // as done so we skip the work on subsequent launches for fresh installs.
        let fm = FileManager.default
        guard fm.fileExists(atPath: plistPath) || fm.fileExists(atPath: statusFile) else {
            UserDefaults.standard.set(true, forKey: Self.cleanupDoneKey)
            return
        }

        // `launchctl bootout` requires the real UID GUI domain. The main app
        // is now desandboxed so we can exec launchctl directly, no applet.
        let guiDomain = "gui/\(getuid())"
        let launchctl = Process()
        launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        launchctl.arguments = ["bootout", "\(guiDomain)/\(label)"]
        launchctl.standardOutput = FileHandle.nullDevice
        launchctl.standardError = FileHandle.nullDevice
        do {
            try launchctl.run()
            launchctl.waitUntilExit()
            logger.info("Legacy helper bootout exit=\(launchctl.terminationStatus, privacy: .public)")
        } catch {
            logger.info("Legacy helper bootout failed: \(error.localizedDescription, privacy: .public)")
        }

        try? fm.removeItem(atPath: plistPath)
        try? fm.removeItem(atPath: statusFile)

        UserDefaults.standard.set(true, forKey: Self.cleanupDoneKey)
        logger.info("Legacy helper cleanup complete")
    }
}

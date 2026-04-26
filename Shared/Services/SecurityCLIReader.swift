import Foundation
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "SecurityCLIReader")

/// Shells out to `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`
/// and extracts `claudeAiOauth.accessToken` from the JSON value Claude Code stores.
///
/// Why shell-out (not `SecItemCopyMatching`):
/// - The Keychain item ACL for "Claude Code-credentials" whitelists
///   `/usr/bin/security` (Apple-signed, stable identity). It does NOT
///   whitelist arbitrary third-party apps, even when correctly signed.
/// - Direct `SecItemCopyMatching` from TokenEater would trip the ACL
///   denial prompt every time; routing through `security` via `Process`
///   sails through silently once the user clicked "Always Allow" once.
/// - Requires the main app to be desandboxed (sandboxed apps cannot
///   `Process.run()` arbitrary binaries).
final class SecurityCLIReader: SecurityCLIReaderProtocol, @unchecked Sendable {
    private let service: String

    init(service: String = "Claude Code-credentials") {
        self.service = service
    }

    func readToken() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", service, "-w"]

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        do {
            try task.run()
        } catch {
            logger.info("security launch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            // Common exit codes: 44 (item not found), 45 (ACL denied).
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return Self.extractToken(fromKeychainPassword: raw)
    }

    /// Parses the password payload `/usr/bin/security` returned for the
    /// "Claude Code-credentials" item and pulls out
    /// `claudeAiOauth.accessToken`. Pure function so it's tested in
    /// isolation - the Process spawn above doesn't need to run.
    /// Returns nil if the payload is empty, isn't JSON, doesn't carry
    /// the expected nested keys, or the access token field is empty.
    static func extractToken(fromKeychainPassword raw: String) -> String? {
        guard let jsonData = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        return token
    }
}

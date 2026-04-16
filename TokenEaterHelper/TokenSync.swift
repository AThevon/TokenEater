import Foundation

final class TokenSync {
    private let interval: TimeInterval
    private let outputURL: URL
    private let helperVersion: String

    init(interval: TimeInterval) {
        self.interval = interval
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        self.outputURL = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/com.tokeneater.shared/keychain-token.json")
        self.helperVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    func runForever() -> Never {
        // Signal-based wake-up: SIGUSR1 from the main app (via `launchctl kickstart
        // -k` or kill) interrupts the sleep and triggers an immediate resync.
        signal(SIGUSR1, { _ in })

        while true {
            performSync()
            Thread.sleep(forTimeInterval: interval)
        }
    }

    func performSync() {
        guard let token = readKeychain() else {
            writeStatus(status: "no-token", token: nil, error: "security returned no password")
            return
        }
        writeStatus(status: "ok", token: token, error: nil)
    }

    private func readKeychain() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        do {
            try task.run()
        } catch {
            return nil
        }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        // Claude Code stores the whole JSON blob in the Keychain value. Extract
        // claudeAiOauth.accessToken - same shape used by TokenProvider elsewhere.
        guard let jsonData = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }

        return token
    }

    private func writeStatus(status: String, token: String?, error: String?) {
        var payload: [String: Any] = [
            "status": status,
            "lastSyncAt": ISO8601DateFormatter().string(from: Date()),
            "helperVersion": helperVersion,
        ]
        if let token { payload["token"] = token }
        if let error { payload["error"] = error }

        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        let parent = outputURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // Atomic write via a temp file + rename so partial reads are impossible.
        let tmpURL = parent.appendingPathComponent(".keychain-token.json.tmp")
        do {
            try data.write(to: tmpURL, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tmpURL.path
            )
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tmpURL)
        } catch {
            // Best effort - next tick will retry.
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }
}

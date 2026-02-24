import Foundation
import AppKit

enum UpdateError: LocalizedError {
    case invalidResponse
    case scriptWriteFailed
    case scriptLaunchFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return String(localized: "update.error.response")
        case .scriptWriteFailed: return String(localized: "update.error.script")
        case .scriptLaunchFailed: return String(localized: "update.error.launch")
        }
    }
}

final class UpdateService: UpdateServiceProtocol, @unchecked Sendable {
    private let repo = "AThevon/TokenEater"

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var realHomeDirectory: String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }

    private var updateScriptPath: String {
        "\(realHomeDirectory)/Library/Application Support/com.tokeneater.shared/update.command"
    }

    // MARK: - Check

    func checkForUpdate() async throws -> UpdateInfo? {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.invalidResponse
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let remoteVersion = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName

        guard isNewer(remoteVersion, than: currentVersion) else {
            return nil
        }

        guard let releaseURL = URL(string: release.htmlURL) else {
            throw UpdateError.invalidResponse
        }

        let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }

        return UpdateInfo(
            version: remoteVersion,
            releaseNotes: release.body,
            downloadURL: dmgAsset.flatMap { URL(string: $0.browserDownloadURL) },
            releaseURL: releaseURL
        )
    }

    // MARK: - Update

    func launchBrewUpdate() throws {
        let script = """
#!/bin/bash
# TokenEater Auto-Update

if [ -x "/opt/homebrew/bin/brew" ]; then
    BREW="/opt/homebrew/bin/brew"
elif [ -x "/usr/local/bin/brew" ]; then
    BREW="/usr/local/bin/brew"
else
    echo "Homebrew not found."
    echo "Run manually: brew upgrade --cask tokeneater"
    read -p "Press Enter to close..."
    exit 1
fi

echo "Updating TokenEater..."
$BREW upgrade --cask tokeneater

if [ $? -eq 0 ]; then
    echo "Update complete! Relaunching..."
    sleep 1
    open /Applications/TokenEater.app
else
    echo "Update failed. Try: brew upgrade --cask tokeneater"
    read -p "Press Enter to close..."
fi

rm -f "$0"
"""

        let dir = (updateScriptPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        guard FileManager.default.createFile(
            atPath: updateScriptPath,
            contents: script.data(using: .utf8)
        ) else {
            throw UpdateError.scriptWriteFailed
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: updateScriptPath
        )

        let url = URL(fileURLWithPath: updateScriptPath)
        guard NSWorkspace.shared.open(url) else {
            // Fallback: copy brew command to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew upgrade --cask tokeneater", forType: .string)
            throw UpdateError.scriptLaunchFailed
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Version comparison

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}

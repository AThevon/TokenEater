import Foundation
import AppKit

enum UpdateError: LocalizedError {
    case invalidResponse
    case scriptLaunchFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return String(localized: "update.error.response")
        case .scriptLaunchFailed: return String(localized: "update.error.launch")
        }
    }
}

final class UpdateService: UpdateServiceProtocol, @unchecked Sendable {
    private let repo = "AThevon/TokenEater"

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
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
        let brewCmd = "BREW=$([ -x /opt/homebrew/bin/brew ] && echo /opt/homebrew/bin/brew || echo /usr/local/bin/brew); $BREW update; $BREW upgrade --cask --greedy tokeneater && sleep 1 && open /Applications/TokenEater.app"

        let source = "tell application \"Terminal\"\nactivate\ndo script \"\(brewCmd)\"\nend tell"

        guard let script = NSAppleScript(source: source) else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew update && brew upgrade --cask --greedy tokeneater", forType: .string)
            throw UpdateError.scriptLaunchFailed
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        if errorInfo != nil {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew update && brew upgrade --cask --greedy tokeneater", forType: .string)
            throw UpdateError.scriptLaunchFailed
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

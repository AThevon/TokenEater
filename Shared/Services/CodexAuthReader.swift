import Foundation

/// Reads `~/.codex/auth.json`, the file Codex CLI writes with mode 0600 after a
/// ChatGPT login.
///
/// Deliberately narrow: plain file I/O, no shell-outs, no Keychain, and no
/// writes. Newer Codex builds can be configured to keep the same JSON in the
/// Keychain instead (`cli_auth_credentials_store = "keyring"`), which surfaces
/// here as `.noCredentials`; supporting that store needs a `/usr/bin/security`
/// shell-out because the Keychain item's ACL whitelists the `codex` binary.
final class CodexAuthReader: CodexAuthReaderProtocol, @unchecked Sendable {

    // MARK: - Private Properties

    private let homeDirectory: URL

    // MARK: - Initializers

    /// - Parameters:
    ///   - environment: injected for tests; production passes the process env.
    ///   - overridePath: user-configured Codex home, when set in Settings.
    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        overridePath: String? = nil
    ) {
        if let overridePath, !overridePath.isEmpty {
            homeDirectory = URL(fileURLWithPath: (overridePath as NSString).expandingTildeInPath)
        } else if let fromEnv = environment["CODEX_HOME"], !fromEnv.isEmpty {
            // Only ever set for an app launched from a shell; a Finder /
            // LaunchServices launch inherits no shell environment.
            homeDirectory = URL(fileURLWithPath: (fromEnv as NSString).expandingTildeInPath)
        } else {
            homeDirectory = URL(fileURLWithPath: Self.realHomeDirectory).appendingPathComponent(".codex")
        }
    }

    // MARK: - Type Properties

    /// `FileManager.homeDirectoryForCurrentUser` returns the container path in a
    /// sandboxed process, so the real home is resolved through the passwd entry,
    /// as everywhere else in the app.
    private static var realHomeDirectory: String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }

    // MARK: - CodexAuthReaderProtocol

    var codexHomeURL: URL { homeDirectory }

    var authFileURL: URL { homeDirectory.appendingPathComponent("auth.json") }

    func readCredentials() -> CodexCredentials? {
        guard let credentials = parse(), credentials.isTrackable else { return nil }
        return credentials
    }

    func authState() -> CodexAuthState {
        guard FileManager.default.fileExists(atPath: homeDirectory.path) else { return .notInstalled }
        guard let credentials = parse() else { return .noCredentials }
        // Only an actual API-key login earns that state. A ChatGPT-mode file
        // with no access token is a logged-out or half-written one, and saying
        // "API key" there would send the user to the wrong fix.
        guard credentials.isTrackable else {
            return credentials.isAPIKeyMode ? .apiKeyOnly : .noCredentials
        }
        return .chatgpt(
            accountId: credentials.accountId,
            planType: credentials.planType,
            expiresAt: credentials.expiresAt
        )
    }

    // MARK: - Private Methods

    /// Parses the file into credentials regardless of auth mode, so `authState`
    /// can tell "API key" apart from "nothing there". `JSONSerialization` rather
    /// than `Codable`: an unexpected top-level shape then degrades to nil
    /// instead of throwing through every call site.
    private func parse() -> CodexCredentials? {
        guard let data = FileManager.default.contents(atPath: authFileURL.path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let authMode = json["auth_mode"] as? String
        let tokens = json["tokens"] as? [String: Any]
        let accessToken = tokens?["access_token"] as? String ?? ""

        // An API-key login has no tokens object at all; report it so the UI can
        // explain why there is nothing to track instead of showing an error.
        if accessToken.isEmpty {
            guard let mode = authMode, !mode.isEmpty else { return nil }
            return CodexCredentials(
                accessToken: "",
                accountId: nil,
                authMode: mode,
                lastRefresh: nil,
                expiresAt: nil,
                planType: nil
            )
        }

        return CodexCredentials(
            accessToken: accessToken,
            accountId: tokens?["account_id"] as? String ?? JWTClaims.chatGPTAccountID(of: accessToken),
            authMode: authMode,
            lastRefresh: (json["last_refresh"] as? String).flatMap(Self.parseISODate),
            expiresAt: JWTClaims.expiration(of: accessToken),
            planType: JWTClaims.chatGPTPlanType(of: accessToken)
        )
    }

    /// Codex writes RFC 3339 with microsecond precision, which the plain
    /// internet-date-time parser rejects.
    private static func parseISODate(_ raw: String) -> Date? {
        isoWithFractionalSeconds.date(from: raw) ?? isoPlain.date(from: raw)
    }

    private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

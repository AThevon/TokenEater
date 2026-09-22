import Foundation

/// Why reading Claude Code's Keychain item produced no token.
///
/// The distinction is the user's business, not just the log's: "there is no
/// such item" and "macOS refused" call for different fixes, and both used to
/// end as the same silent fall-through to the next source. The app then ran
/// on whatever an older file still held, and reported the resulting 401 as
/// "OAuth token expired, relaunch Claude Code", which is advice that cannot
/// work: relaunching refreshes the Keychain item, the one we failed to read
/// (#273).
enum KeychainReadFailure: String, Codable, Equatable, Error, Sendable {
    /// `security` exit 44: no "Claude Code-credentials" item at all.
    case notFound
    /// `security` exit 45: the item is there and access was refused.
    case accessDenied
    /// The 3s watchdog fired. On macOS 26+ the spawned `security` can block
    /// indefinitely on Keychain authorization for a headless app (#217).
    case timedOut
    /// `/usr/bin/security` could not be spawned.
    case launchFailed
    /// Exit 0, but the payload carried no `claudeAiOauth.accessToken`.
    case unusablePayload
    /// Any other non-zero exit.
    case unknown

    /// Short tag for the diagnostic report, never shown in the UI.
    var reportLabel: String { rawValue }

    /// Whether the live token was there and we simply could not have it. These
    /// are the two failures that leave a working Claude Code install looking
    /// broken; `notFound` is the legitimate case of a machine that keeps its
    /// credentials in a file.
    var blockedLiveRead: Bool { self == .accessDenied || self == .timedOut }
}

/// Where the token in use came from, in `TokenProvider`'s priority order.
enum TokenSource: String, Codable, Equatable, Sendable {
    case keychainCLI
    case credentialsFile
    case claudeDesktop
    case keychainDirect

    /// True for the two sources that read the live Keychain item.
    var isKeychain: Bool { self == .keychainCLI || self == .keychainDirect }

    var reportLabel: String { rawValue }
}

/// What the last read of the token sources found: where the token came from,
/// and why the Keychain did not answer when it did not.
struct TokenDiagnostic: Equatable, Sendable {
    let source: TokenSource?
    let keychainFailure: KeychainReadFailure?

    static let unknown = TokenDiagnostic(source: nil, keychainFailure: nil)

    /// True when a token is in use, it came from a file, and the Keychain read
    /// was blocked rather than absent. That is the combination that produces
    /// an expired token no amount of relaunching Claude Code can fix.
    var isStaleFallback: Bool {
        guard let source, !source.isKeychain else { return false }
        return keychainFailure?.blockedLiveRead == true
    }

    /// What to tell the user when the request came back unauthorized, or nil
    /// when the plain "token expired" answer is the true one.
    var authFailureHint: String? {
        guard let failure = keychainFailure, failure.blockedLiveRead else { return nil }
        switch (failure, source) {
        case (.accessDenied, .some):
            return String(localized: "error.keychain.denied.fallback")
        case (.accessDenied, nil):
            return String(localized: "error.keychain.denied.notoken")
        case (.timedOut, .some):
            return String(localized: "error.keychain.timeout.fallback")
        case (.timedOut, nil):
            return String(localized: "error.keychain.timeout.notoken")
        default:
            return nil
        }
    }
}

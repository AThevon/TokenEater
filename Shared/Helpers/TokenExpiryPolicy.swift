import Foundation

/// When a Claude login counts as expired, and when an expired one stops
/// being routine.
///
/// TokenEater only reads the login; Claude Code renews it whenever it runs.
/// Someone who works in the Claude desktop app rather than the CLI can go a
/// whole day with nothing renewing the Keychain item, and the calm "waiting
/// for Claude Code" state used to sit there forever over numbers that had
/// stopped moving (#268). The first hour after expiry is the ordinary lag
/// before the next CLI run; past it, nothing is coming and the user has to
/// be told.
enum TokenExpiryPolicy {
    /// A token this close to its expiry is treated as already expired, so a
    /// fresher source is preferred over one that would die mid-request.
    static let expiryMargin: TimeInterval = 60

    /// How long a login may sit expired before the app stops waiting quietly.
    static let escalationDelay: TimeInterval = 3600

    /// True only when the expiry is known and (nearly) past. An unknown
    /// expiry is not evidence of anything, so it never counts as expired.
    static func isExpired(_ expiresAt: Date?, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(expiryMargin)
    }

    /// The expiry date, once the login has been expired for longer than
    /// `escalationDelay`; nil while it is valid, unknown, or only recently
    /// expired. The date doubles as the episode's identity: a renewed login
    /// expires later, which starts the next episode.
    static func staleSince(expiresAt: Date?, now: Date = Date()) -> Date? {
        guard let expiresAt, now.timeIntervalSince(expiresAt) > escalationDelay else { return nil }
        return expiresAt
    }
}

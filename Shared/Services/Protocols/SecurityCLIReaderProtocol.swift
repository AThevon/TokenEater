import Foundation

/// What one attempt at Claude Code's Keychain item found.
///
/// A plain optional was the whole bug: "no such item", "macOS refused" and
/// "the item we got holds no login" all reached the caller as the same
/// nothing, so the app fell back to an older token on disk and reported the
/// resulting 401 as an expired token (#273, #268).
struct KeychainRead: Equatable, Sendable {
    let token: String?
    let failure: KeychainReadFailure?
    /// How many Keychain items carry the service name. Above one means a
    /// second item is shadowing the login, which is worth carrying into the
    /// diagnostic report even once the read has worked around it.
    let matchingItems: Int
    /// When the token stops working, as Claude Code wrote it. TokenEater only
    /// reads the item, so an expiry in the past is the true answer to "why did
    /// the API say no" and the one case where telling the user to run Claude
    /// Code is right (#268).
    var expiresAt: Date?

    static func success(_ token: String, matchingItems: Int = 1, expiresAt: Date? = nil) -> KeychainRead {
        KeychainRead(token: token, failure: nil, matchingItems: matchingItems, expiresAt: expiresAt)
    }

    static func failure(_ failure: KeychainReadFailure, matchingItems: Int = 0) -> KeychainRead {
        KeychainRead(token: nil, failure: failure, matchingItems: matchingItems)
    }
}

/// Reads the OAuth token by shelling out to `/usr/bin/security`. Works only
/// when the main app is NOT sandboxed (the sandbox rejects `Process.run()`
/// for arbitrary executables). The `/usr/bin/security` binary has a stable
/// Apple signing identity that Claude Code's Keychain item ACL whitelists,
/// so once the user grants access once it sticks across app updates.
protocol SecurityCLIReaderProtocol: Sendable {
    func read() -> KeychainRead
}

extension SecurityCLIReaderProtocol {
    /// The old shape, for the call sites that only need to know whether a
    /// token exists.
    func readToken() -> String? { read().token }
}

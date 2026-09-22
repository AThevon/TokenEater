import Foundation

/// Reads the OAuth token by shelling out to `/usr/bin/security`. Works only
/// when the main app is NOT sandboxed (the sandbox rejects `Process.run()`
/// for arbitrary executables). The `/usr/bin/security` binary has a stable
/// Apple signing identity that Claude Code's Keychain item ACL whitelists,
/// so once the user grants access once it sticks across app updates.
protocol SecurityCLIReaderProtocol: Sendable {
    /// The token, or why there is none. The failure is part of the contract
    /// rather than a log line: the caller falls back to a file on every kind
    /// of failure, and only the failure says whether that fallback is the
    /// normal path or a machine whose live token we were refused (#273).
    func read() -> Result<String, KeychainReadFailure>
}

extension SecurityCLIReaderProtocol {
    /// The old shape, for the call sites that only need to know whether a
    /// token exists.
    func readToken() -> String? { try? read().get() }
}

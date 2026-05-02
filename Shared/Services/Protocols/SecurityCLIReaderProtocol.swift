import Foundation

/// Reads the OAuth token by shelling out to `/usr/bin/security`. Works only
/// when the main app is NOT sandboxed (the sandbox rejects `Process.run()`
/// for arbitrary executables). The `/usr/bin/security` binary has a stable
/// Apple signing identity that Claude Code's Keychain item ACL whitelists,
/// so once the user grants access once it sticks across app updates.
protocol SecurityCLIReaderProtocol: Sendable {
    func readToken() -> String?
}

import Foundation

// MARK: - Helper entry point
//
// This binary is NOT sandboxed. It is loaded by the user's LaunchAgent so it
// can shell out to /usr/bin/security - the only process explicitly whitelisted
// in the ACL of the "Claude Code-credentials" Keychain item. The sandboxed
// main TokenEater app cannot do this itself.
//
// The helper runs a simple loop: read the Keychain, write the decoded access
// token to a shared JSON file, sleep, repeat. Configurable interval via the
// SYNC_INTERVAL env var (floor of 30s).

let defaultInterval: TimeInterval = 300 // 5 minutes

let interval: TimeInterval = {
    guard let raw = ProcessInfo.processInfo.environment["SYNC_INTERVAL"],
          let value = TimeInterval(raw),
          value >= 30 else {
        return defaultInterval
    }
    return value
}()

let sync = TokenSync(interval: interval)
sync.runForever()

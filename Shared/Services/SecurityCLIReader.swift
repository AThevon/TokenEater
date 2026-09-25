import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "SecurityCLIReader")

/// Shells out to `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`
/// and extracts `claudeAiOauth.accessToken` from the JSON value Claude Code stores.
///
/// Why shell-out (not `SecItemCopyMatching`):
/// - The Keychain item ACL for "Claude Code-credentials" whitelists
///   `/usr/bin/security` (Apple-signed, stable identity). It does NOT
///   whitelist arbitrary third-party apps, even when correctly signed.
/// - Direct `SecItemCopyMatching` from TokenEater would trip the ACL
///   denial prompt every time; routing through `security` via `Process`
///   sails through silently once the user clicked "Always Allow" once.
/// - Requires the main app to be desandboxed (sandboxed apps cannot
///   `Process.run()` arbitrary binaries).
///
/// Why it reads every matching item rather than the first one: a lookup by
/// service name alone returns whichever item the Keychain hands back first,
/// and several items can carry the name "Claude Code-credentials". A second
/// one holding only MCP OAuth state shadows the real login, the read comes
/// back with no `claudeAiOauth` in it, and the app falls through to an older
/// token on disk. Reinstalling and redoing onboarding cannot fix that,
/// because nothing about it lives in TokenEater's own config (#268).
final class SecurityCLIReader: SecurityCLIReaderProtocol, @unchecked Sendable {
    /// Lists the account names of every Keychain item under a service name.
    /// Attributes only, never the data, so it stays silent: the ACL guards
    /// the payload, not the item's existence.
    typealias AccountLister = @Sendable (String) -> [String]

    private let service: String
    private let accountLister: AccountLister

    init(service: String = "Claude Code-credentials", accountLister: AccountLister? = nil) {
        self.service = service
        self.accountLister = accountLister ?? Self.listAccounts
    }

    func read() -> KeychainRead {
        let accounts = accountLister(service)

        // One item, or an enumeration that told us nothing: the plain lookup,
        // exactly as before.
        guard accounts.count > 1 else {
            return single(account: accounts.first, matchingItems: max(accounts.count, 1))
        }

        logger.info("\(accounts.count, privacy: .public) Keychain items share the service name; reading each")
        let payloads: [(account: String, raw: String)] = accounts.compactMap { account in
            guard case .success(let raw) = runSecurity(account: account) else { return nil }
            return (account, raw)
        }
        guard let best = Self.bestCredential(among: payloads) else {
            return .failure(.unusablePayload, matchingItems: accounts.count)
        }
        return .success(best.credential.token, matchingItems: accounts.count, expiresAt: best.credential.expiresAt)
    }

    // MARK: - One item

    private func single(account: String?, matchingItems: Int) -> KeychainRead {
        switch runSecurity(account: account) {
        case .failure(let failure):
            return .failure(failure, matchingItems: matchingItems)
        case .success(let raw):
            guard let credential = Self.credential(fromKeychainPassword: raw) else {
                return .failure(.unusablePayload, matchingItems: matchingItems)
            }
            return .success(credential.token, matchingItems: matchingItems, expiresAt: credential.expiresAt)
        }
    }

    /// Runs `security` once and returns the raw password payload.
    private func runSecurity(account: String?) -> Result<String, KeychainReadFailure> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        var arguments = ["find-generic-password", "-s", service]
        if let account { arguments += ["-a", account] }
        arguments.append("-w")
        task.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        do {
            try task.run()
        } catch {
            logger.info("security launch failed: \(error.localizedDescription, privacy: .public)")
            return .failure(.launchFailed)
        }
        // Guard against a hung child. On macOS 26 the spawned `security` process
        // can block indefinitely on Keychain authorization when launched by a
        // headless (LSUIElement) GUI app, so waitUntilExit() never returns and a
        // caller on the main thread beachballs (see #217). Wait on a background
        // thread with a 3s timeout, then fall through to the next source.
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            task.waitUntilExit()
            done.signal()
        }
        if done.wait(timeout: .now() + 3) == .timedOut {
            task.terminate()
            logger.info("security read timed out after 3s; falling through to next source")
            return .failure(.timedOut)
        }
        guard task.terminationStatus == 0 else {
            return .failure(Self.failure(forExitCode: task.terminationStatus))
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return .failure(.unusablePayload)
        }
        return .success(raw)
    }

    /// `security`'s own exit codes. 44 and 45 are the two that say something
    /// the user can act on, so they are the two that are named.
    static func failure(forExitCode code: Int32) -> KeychainReadFailure {
        switch code {
        case 44: return .notFound
        case 45: return .accessDenied
        default: return .unknown
        }
    }

    // MARK: - Enumeration

    /// Every account name stored under this service. Asks for attributes and
    /// never for data, which is what keeps it free of the ACL prompt.
    private static func listAccounts(service: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    // MARK: - Payload parsing

    /// One Claude Code login as the Keychain stores it.
    struct KeychainCredential: Equatable {
        let token: String
        /// When the access token stops working. Claude Code refreshes it when
        /// it runs; TokenEater only reads it, so this is the honest answer to
        /// "why did the API say no" rather than a thing it can act on.
        let expiresAt: Date?
    }

    /// Parses the password payload `/usr/bin/security` returned for the
    /// "Claude Code-credentials" item and pulls out
    /// `claudeAiOauth.accessToken`. Pure function so it's tested in
    /// isolation - the Process spawn above doesn't need to run.
    /// Returns nil if the payload is empty, isn't JSON, doesn't carry
    /// the expected nested keys, or the access token field is empty.
    static func extractToken(fromKeychainPassword raw: String) -> String? {
        credential(fromKeychainPassword: raw)?.token
    }

    static func credential(fromKeychainPassword raw: String) -> KeychainCredential? {
        guard let jsonData = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            return nil
        }
        return KeychainCredential(token: token, expiresAt: expiry(from: oauth["expiresAt"]))
    }

    /// Claude Code writes `expiresAt` in milliseconds. Seconds are accepted
    /// too rather than guessed at: a value small enough to be seconds is
    /// read as seconds, so a format change does not silently land the expiry
    /// in 1970.
    private static func expiry(from value: Any?) -> Date? {
        let raw: Double
        switch value {
        case let number as Double: raw = number
        case let number as Int: raw = Double(number)
        case let string as String: guard let parsed = Double(string) else { return nil }; raw = parsed
        default: return nil
        }
        guard raw > 0 else { return nil }
        let seconds = raw > 1_000_000_000_000 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds)
    }

    /// The item that actually holds a Claude Code login, preferring the one
    /// that lasts longest when more than one does. A shadowing item carries no
    /// `claudeAiOauth` at all, so it drops out here rather than deciding the
    /// read.
    static func bestCredential(
        among payloads: [(account: String, raw: String)]
    ) -> (account: String, credential: KeychainCredential)? {
        payloads
            .compactMap { payload -> (account: String, credential: KeychainCredential)? in
                guard let credential = credential(fromKeychainPassword: payload.raw) else { return nil }
                return (payload.account, credential)
            }
            .max { lhs, rhs in
                (lhs.credential.expiresAt ?? .distantPast) < (rhs.credential.expiresAt ?? .distantPast)
            }
    }
}

import Foundation
import CryptoKit

/// Path and Keychain-service maths for Claude Code config directories.
///
/// Claude Code keeps one login per config directory. With `CLAUDE_CONFIG_DIR`
/// unset it uses `~/.claude` and the Keychain service "Claude Code-credentials";
/// with it set, the service gains a suffix made of the first eight hex digits
/// of the sha256 of the variable's value, exactly as the user typed it. The
/// same folder can therefore hash differently depending on how it was spelled
/// (a trailing slash, an unexpanded `~`), which is why `serviceCandidates`
/// returns every plausible spelling rather than one answer.
///
/// Stateless and free of Keychain access: callers decide what to look up.
/// `home` is a parameter everywhere so tests never depend on the real one.
enum ClaudeConfigDirResolver {
    static let baseService = "Claude Code-credentials"

    /// The user's real home, also inside the widget's sandbox, where
    /// `FileManager.homeDirectoryForCurrentUser` points at the container.
    static func realHome() -> String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }

    /// The default config directory, `<home>/.claude`.
    static func defaultDirectory(home: String) -> String {
        normalize(home, home: home) + "/.claude"
    }

    /// `~` expanded, relative paths taken from home, `.` and `..` folded, no
    /// trailing slash, Unicode NFC. Purely textual: symlinks are left alone.
    static func normalize(_ path: String, home: String) -> String {
        var raw = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHome = home.hasSuffix("/") && home.count > 1 ? String(home.dropLast()) : home
        if raw == "~" {
            raw = cleanHome
        } else if raw.hasPrefix("~/") {
            raw = cleanHome + raw.dropFirst(1)
        } else if !raw.hasPrefix("/") {
            raw = cleanHome + "/" + raw
        }
        var standardized = URL(fileURLWithPath: raw).standardized.path
        while standardized.count > 1, standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        return standardized.precomposedStringWithCanonicalMapping
    }

    static func isDefault(_ path: String, home: String) -> Bool {
        normalize(path, home: home) == defaultDirectory(home: home)
    }

    /// The Keychain service names Claude Code may have used for this folder,
    /// most likely first and without duplicates: the normalized absolute
    /// path, the same with a trailing slash, the `~/` spelling, then the path
    /// with symlinks resolved.
    ///
    /// The default folder leads with the base service, which is what Claude
    /// Code uses with `CLAUDE_CONFIG_DIR` unset. Claude Code decides on the
    /// suffix from whether the variable is set, not from where it points, so
    /// someone who exports `CLAUDE_CONFIG_DIR=~/.claude` explicitly gets the
    /// suffixed spellings; they follow as fallbacks.
    static func serviceCandidates(for path: String, home: String) -> [String] {
        let normalized = normalize(path, home: home)
        let suffixed = suffixedCandidates(normalized: normalized, home: home)
        guard !isDefault(path, home: home) else {
            return [baseService] + suffixed.filter { $0 != baseService }
        }
        return suffixed
    }

    private static func suffixedCandidates(normalized: String, home: String) -> [String] {
        var inputs = [normalized, normalized + "/"]
        let tilde = displayPath(normalized, home: home)
        if tilde != normalized { inputs.append(tilde) }
        let resolved = URL(fileURLWithPath: normalized).resolvingSymlinksInPath().path
            .precomposedStringWithCanonicalMapping
        inputs.append(resolved)

        var seen = Set<String>()
        return inputs
            .map(service(forHashInput:))
            .filter { seen.insert($0).inserted }
    }

    /// The service Claude Code derives from a `CLAUDE_CONFIG_DIR` value.
    static func service(forHashInput input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return baseService + "-" + hex.prefix(8)
    }

    /// The short tail of a suffixed service ("-1a2b3c4d"), for the diagnostic
    /// report. The base service has none.
    static func serviceSuffix(_ service: String) -> String {
        guard service.hasPrefix(baseService) else { return service }
        let tail = service.dropFirst(baseService.count)
        return tail.isEmpty ? "" : String(tail)
    }

    /// A name for the account behind a folder: `.claude-work` gives "Work",
    /// `.claude` gives "Claude". Never longer than the name limit, and made
    /// unique against `existing` with a " 2", " 3" suffix.
    static func proposedName(forConfigDir path: String, existing: [String]) -> String {
        var component = URL(fileURLWithPath: path).lastPathComponent
        while component.hasPrefix(".") { component.removeFirst() }
        let lower = component.lowercased()
        for prefix in ["claude-", "claude_", "claude."] where lower.hasPrefix(prefix) {
            component = String(component.dropFirst(prefix.count))
            break
        }
        let base: String
        if component.isEmpty || component.lowercased() == "claude" {
            base = AccountNameRules.defaultName
        } else {
            base = AccountNameRules.sanitize(component.prefix(1).uppercased() + component.dropFirst())
        }

        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var index = 2
        while true {
            let suffix = " \(index)"
            let stem = String(base.prefix(AccountNameRules.maxLength - suffix.count))
                .trimmingCharacters(in: .whitespaces)
            let candidate = stem + suffix
            if !taken.contains(candidate.lowercased()) { return candidate }
            index += 1
        }
    }

    /// An email reduced to what tells two logins apart at a glance: the first
    /// character, three dots, the domain ("m•••@acme.com"). Settings shows it
    /// in memory only; it is never stored and never reaches the widget.
    static func maskEmail(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        guard let at = trimmed.lastIndex(of: "@"), at != trimmed.startIndex else {
            return String(first) + "•••"
        }
        return String(first) + "•••" + trimmed[at...]
    }

    /// One-way fingerprint of a login's identity. Two folders signed in to
    /// the same account and organization give the same digest; the uuids
    /// themselves are never kept.
    static func identityDigest(accountUUID: String, organizationUUID: String?) -> String {
        let input = accountUUID.lowercased() + ":" + (organizationUUID?.lowercased() ?? "")
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `~/...` for anything under home, the full path otherwise. What the UI
    /// and the diagnostic report show, so neither carries the user name.
    static func displayPath(_ path: String, home: String) -> String {
        let normalized = normalize(path, home: home)
        let cleanHome = normalize(home, home: home)
        if normalized == cleanHome { return "~" }
        if normalized.hasPrefix(cleanHome + "/") {
            return "~" + normalized.dropFirst(cleanHome.count)
        }
        return normalized
    }

    /// The command that opens Claude Code on this folder, to run `/login` in.
    /// Paths that need quoting use `$HOME`, since `~` does not expand inside
    /// quotes.
    static func loginCommand(forConfigDir path: String, home: String) -> String {
        let shown = displayPath(path, home: home)
        let safe = shown.allSatisfy { $0.isLetter || $0.isNumber || "~/._-+".contains($0) }
        if safe { return "CLAUDE_CONFIG_DIR=\(shown) claude" }
        let underHome = shown.hasPrefix("~")
        let tail = underHome ? String(shown.dropFirst()) : shown
        let escaped = tail
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return "CLAUDE_CONFIG_DIR=\"\(underHome ? "$HOME" : "")\(escaped)\" claude"
    }
}

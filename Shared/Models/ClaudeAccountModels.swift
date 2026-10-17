import Foundation

// MARK: - Account identity
//
// A Claude account is one Claude Code login, held in one config directory
// (`~/.claude` by default, or whatever `CLAUDE_CONFIG_DIR` points at). The
// main account is the one the app has always tracked; every other account is
// added explicitly by the user. Nothing here does I/O: persistence lives in
// `AccountsStore`, path and Keychain service maths in `ClaudeConfigDirResolver`.

/// Stable identifier of a tracked Claude account.
///
/// `main` for the account the app has always tracked, `acct-<lowercased uuid>`
/// for an added one. The raw value ends up in `UserDefaults` key suffixes and
/// in file names inside the shared directory, so decoding refuses anything
/// that is not one of those two shapes rather than trusting a stored string.
struct AccountID: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let main = AccountID(rawValue: "main")

    /// A fresh identifier for an added account.
    static func makeExtra() -> AccountID {
        AccountID(rawValue: "acct-" + UUID().uuidString.lowercased())
    }

    var isMain: Bool { self == .main }

    /// Appended to per-account storage keys. Empty for the main account, so
    /// every key the app wrote before accounts existed keeps its exact name.
    var storageSuffix: String { isMain ? "" : ".\(rawValue)" }

    var id: String { rawValue }

    /// Whether a raw value is one this build would ever have written.
    static func isValid(_ raw: String) -> Bool {
        if raw == "main" { return true }
        guard raw.hasPrefix("acct-") else { return false }
        let body = raw.dropFirst("acct-".count)
        guard !body.isEmpty, body.count <= 64 else { return false }
        return body.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") && !$0.isUppercase }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard Self.isValid(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not an account identifier: \(raw)"
            )
        }
        self.rawValue = raw
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Credential scope

/// Where an account's credentials may come from.
///
/// The scope is what keeps two accounts apart: a token read for one account
/// can only come from that account's own sources, so the "freshest login"
/// fallback (#291) chooses inside one scope and never borrows another
/// account's login.
enum CredentialScope: Equatable, Sendable {
    /// The chain the app has always used: the "Claude Code-credentials"
    /// Keychain service (every item under it, #268), `~/.claude/.credentials.json`
    /// and Claude Desktop's encrypted config.
    case defaultChain
    /// One `CLAUDE_CONFIG_DIR`: the exact suffixed Keychain service Claude Code
    /// writes for that directory, then `<path>/.credentials.json`. Never
    /// Claude Desktop, which holds a login of its own unrelated to the folder.
    case configDir(path: String, service: String)

    /// The config directory itself.
    func directoryPath(home: String) -> String {
        switch self {
        case .defaultChain: return home + "/.claude"
        case .configDir(let path, _): return path
        }
    }

    func credentialsFilePath(home: String) -> String {
        directoryPath(home: home) + "/.credentials.json"
    }

    /// Claude Code's session transcripts, read by History and the insights.
    func projectsURL(home: String) -> URL {
        URL(fileURLWithPath: directoryPath(home: home), isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    /// Claude Code's live session registry, read by the Agent Watchers.
    func sessionsURL(home: String) -> URL {
        URL(fileURLWithPath: directoryPath(home: home), isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    var includesClaudeDesktop: Bool { self == .defaultChain }

    /// The Keychain service read for this scope.
    var keychainService: String {
        switch self {
        case .defaultChain: return ClaudeConfigDirResolver.baseService
        case .configDir(_, let service): return service
        }
    }
}

// MARK: - Account record

/// One tracked Claude account, as persisted under `claudeAccounts.v1`.
///
/// Never holds an email, an account or organization uuid, or an organization
/// name: the identity check keeps only a digest, and the readable details live
/// in memory for Settings alone.
struct ClaudeAccountRecord: Codable, Identifiable, Equatable, Sendable {
    let id: AccountID
    /// Nil means `~/.claude` with the app's historical behaviour, which only
    /// the main account can have.
    var configDir: String?
    /// The exact Keychain service for `configDir`, nil when `configDir` is.
    var service: String?
    var name: String
    var colorHex: String
    /// Always false for the main account, which stops with Claude itself.
    var isPaused: Bool
    var notificationsEnabled: Bool
    /// sha256 of `account.uuid + ":" + organization.uuid`, hex. Never the
    /// uuids themselves.
    var identityDigest: String?
    var addedAt: Date

    init(
        id: AccountID,
        configDir: String? = nil,
        service: String? = nil,
        name: String,
        colorHex: String,
        isPaused: Bool = false,
        notificationsEnabled: Bool = true,
        identityDigest: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.configDir = configDir
        self.service = service
        self.name = name
        self.colorHex = colorHex
        self.isPaused = id.isMain ? false : isPaused
        self.notificationsEnabled = notificationsEnabled
        self.identityDigest = identityDigest
        self.addedAt = addedAt
    }

    /// The main account as it exists before the user touches anything: the
    /// default folder, the default chain, the first palette colour.
    static func defaultMain() -> ClaudeAccountRecord {
        ClaudeAccountRecord(
            id: .main,
            name: AccountNameRules.defaultName,
            colorHex: AccountPalette.presets[0],
            addedAt: Date(timeIntervalSince1970: 0)
        )
    }

    var scope: CredentialScope {
        guard let configDir else { return .defaultChain }
        let service = (self.service?.isEmpty == false ? self.service : nil)
            ?? ClaudeConfigDirResolver.service(forHashInput: configDir)
        return .configDir(path: configDir, service: service)
    }

    var summary: ClaudeAccountSummary {
        ClaudeAccountSummary(id: id, name: name, colorHex: colorHex, isPaused: isPaused)
    }

    private enum CodingKeys: String, CodingKey {
        case id, configDir, service, name, colorHex, isPaused, notificationsEnabled, identityDigest, addedAt
    }

    /// Tolerant: only `id` is required. Anything else missing or of the wrong
    /// type falls back to its default, so a record written by a newer build
    /// still loads here.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(AccountID.self, forKey: .id)
        self.id = id
        let dir = (try? c.decodeIfPresent(String.self, forKey: .configDir)) ?? nil
        self.configDir = (dir?.isEmpty == false) ? dir : nil
        let service = (try? c.decodeIfPresent(String.self, forKey: .service)) ?? nil
        self.service = (service?.isEmpty == false) ? service : nil
        let rawName = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
        self.name = AccountNameRules.sanitize(rawName ?? "")
        let color = (try? c.decodeIfPresent(String.self, forKey: .colorHex)) ?? nil
        self.colorHex = color.flatMap(AccountPalette.normalizedHex) ?? AccountPalette.presets[0]
        let paused = ((try? c.decodeIfPresent(Bool.self, forKey: .isPaused)) ?? nil) ?? false
        self.isPaused = id.isMain ? false : paused
        self.notificationsEnabled = ((try? c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled)) ?? nil) ?? true
        let digest = (try? c.decodeIfPresent(String.self, forKey: .identityDigest)) ?? nil
        self.identityDigest = (digest?.isEmpty == false) ? digest : nil
        self.addedAt = ((try? c.decodeIfPresent(Date.self, forKey: .addedAt)) ?? nil) ?? Date(timeIntervalSince1970: 0)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(configDir, forKey: .configDir)
        try c.encodeIfPresent(service, forKey: .service)
        try c.encode(name, forKey: .name)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encode(isPaused, forKey: .isPaused)
        try c.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try c.encodeIfPresent(identityDigest, forKey: .identityDigest)
        try c.encode(addedAt, forKey: .addedAt)
    }
}

/// The part of a record the surfaces need: who it is, what to call it, which
/// colour marks it, whether it is running.
struct ClaudeAccountSummary: Equatable, Hashable, Sendable, Identifiable {
    let id: AccountID
    let name: String
    let colorHex: String
    let isPaused: Bool
}

/// Reads and writes the account list. The key is absent until the first
/// change, so an install that never adds an account keeps exactly the
/// defaults it had before accounts existed.
enum ClaudeAccountsStorage {
    static let defaultsKey = "claudeAccounts.v1"

    /// The stored list, cleaned: the main account first and exactly once,
    /// unreadable entries dropped, duplicate ids and duplicate folders dropped.
    static func decode(_ data: Data?) -> [ClaudeAccountRecord] {
        var records: [ClaudeAccountRecord] = []
        if let data,
           let decoded = try? JSONDecoder().decode([Lossy<ClaudeAccountRecord>].self, from: data) {
            records = decoded.compactMap(\.value)
        }
        let main = records.first(where: { $0.id.isMain }) ?? .defaultMain()
        var seenIDs: Set<AccountID> = [.main]
        var seenDirs: Set<String> = main.configDir.map { [$0] } ?? []
        var result = [main]
        for record in records where !record.id.isMain {
            // An added account always has a folder of its own: without one it
            // would read the main account's login.
            guard let dir = record.configDir,
                  !seenIDs.contains(record.id),
                  !seenDirs.contains(dir) else { continue }
            seenIDs.insert(record.id)
            seenDirs.insert(dir)
            result.append(record)
        }
        return result
    }

    static func encode(_ records: [ClaudeAccountRecord]) -> Data? {
        try? JSONEncoder().encode(records)
    }

    static func load(from defaults: UserDefaults) -> [ClaudeAccountRecord] {
        decode(defaults.data(forKey: defaultsKey))
    }

    /// The main account's scope, for the services built before any store
    /// exists (History, the session scan): the folder the user chose for it,
    /// or the default chain (#294).
    static func mainScope(defaults: UserDefaults = .standard) -> CredentialScope {
        (load(from: defaults).first ?? .defaultMain()).scope
    }
}

// MARK: - Names and colours

/// The account's identity colour. It marks the account (a dot, a section
/// header, a mode pill) and never tints a value: risk colour stays on the
/// numbers (Smart Color and the thresholds, see `docs/design/COLORING.md`).
/// The presets avoid the greens, ambers, oranges and reds that risk uses.
enum AccountPalette {
    static let presets: [String] = [
        "#5B8DEF", // blue
        "#6366F1", // indigo
        "#8B7CF6", // violet
        "#C084FC", // lilac
        "#F472B6", // pink
        "#22D3EE", // cyan
        "#D6B88A", // sand
        "#94A3B8", // slate
    ]

    /// The first preset no tracked account uses yet, cycling once all eight
    /// are taken.
    static func nextColor(excluding used: [String]) -> String {
        let taken = Set(used.compactMap(normalizedHex))
        if let free = presets.first(where: { !taken.contains($0) }) { return free }
        return presets[taken.count % presets.count]
    }

    /// `#RRGGBB` uppercased, or nil for anything that is not a six-digit hex
    /// colour (with or without the leading `#`).
    static func normalizedHex(_ raw: String) -> String? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + hex
    }
}

enum AccountNameRules {
    /// Longest name the field accepts.
    static let maxLength = 12
    /// Characters a name keeps in the menu bar before the ellipsis.
    static let menuBarVisibleCharacters = 8
    /// What an account is called when nothing better is known.
    static let defaultName = "Claude"

    /// Trimmed, single-line, cut to `maxLength`, never empty.
    static func sanitize(_ raw: String, fallback: String = defaultName) -> String {
        let flattened = raw
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(flattened.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? fallback : cut
    }

    /// The name as the menu bar draws it: eight characters, then an ellipsis
    /// when there were more. The full name lives in tooltips and Settings.
    static func menuBarLabel(_ name: String) -> String {
        guard name.count > menuBarVisibleCharacters else { return name }
        return String(name.prefix(menuBarVisibleCharacters)) + "…"
    }
}

/// How the menu bar marks a group of segments that belong to one account,
/// once two accounts are on.
enum MenuBarAccountLabel: String, Codable, CaseIterable, Sendable {
    /// The account's colour dot alone.
    case dot
    /// The dot followed by the account's short name.
    case dotAndName
}

// MARK: - Identity

/// What the identity check concluded about the login a folder now holds.
enum IdentityVerdict: Equatable, Sendable {
    /// The login is this account's own, or the first one seen for it.
    case accepted
    /// The login belongs to another tracked account.
    case belongsTo(AccountID)
    /// The folder now signs in to an identity no tracked account has.
    case changed(newDigest: String)
}

enum IdentityState: Equatable, Sendable {
    /// No check runs: one account follows whatever login is active (#153).
    case unchecked
    case verified
    /// The profile could not be fetched; the last numbers stay, nothing is
    /// written, and the next tick retries.
    case pending
    case conflict(IdentityVerdict)
}

/// One pill of the mode switcher: a provider mode, and for Claude the account
/// it shows.
struct ModeChoice: Hashable, Identifiable, Sendable {
    let mode: ProviderMode
    /// Non-nil only for `.claude`.
    let account: AccountID?

    init(mode: ProviderMode, account: AccountID? = nil) {
        self.mode = mode
        self.account = mode == .claude ? (account ?? .main) : nil
    }

    var id: String {
        guard let account else { return mode.rawValue }
        return mode.rawValue + account.storageSuffix
    }
}

// MARK: - Discovery

/// A Claude Code config folder the add-account sheet can offer, as seen
/// without reading any credential: the folder's own files, and whether a
/// Keychain item exists under one of the service names Claude Code would
/// have used for it (asked of the item's attributes, which no ACL guards).
struct ConfigDirCandidate: Equatable, Identifiable, Sendable {
    /// Normalized absolute path.
    let path: String
    /// The `~/...` spelling shown in the UI.
    let displayPath: String
    /// The first service name that has a Keychain item, nil when none does.
    let matchedService: String?
    /// `<path>/.credentials.json` exists.
    let hasCredentialsFile: Bool
    /// When Claude Code last wrote a transcript there (`<path>/projects`).
    let lastActivity: Date?
    /// False for a path that is not a folder (a chosen folder deleted since,
    /// or a typo).
    let exists: Bool

    var hasLogin: Bool { matchedService != nil || hasCredentialsFile }
    var id: String { path }
}

// MARK: - Connecting

/// A folder whose login was read and identified, waiting for the user to name
/// it. The plan, organization and masked email live in memory only, for the
/// sheet; none of them is ever persisted.
struct PendingAccount: Equatable, Sendable {
    /// Normalized absolute path.
    let configDir: String
    /// The Keychain service the login was read from, or would be.
    let service: String
    let digest: String
    let plan: PlanType
    let organizationName: String?
    let maskedEmail: String?
    let proposedName: String
    let proposedColorHex: String
}

/// What connecting a folder found. Everything but `.ready` is refused, and
/// says why in terms the user can act on.
enum AccountConnectResult: Equatable, Sendable {
    case ready(PendingAccount)
    /// Neither a Keychain item nor a `.credentials.json` for this exact path.
    case noLogin(command: String)
    /// `security` exit 45: macOS refused the read.
    case accessDenied
    /// The 3s watchdog fired before `security` answered.
    case timedOut
    /// The login exists but Anthropic refused it. Without a profile there is
    /// no telling whose account it is, so it cannot be added yet.
    case expired(command: String)
    /// The folder signs in to an account that is already tracked.
    case duplicate(of: ClaudeAccountSummary)
    /// The folder itself is already tracked.
    case alreadyTracked
    case network(String)
}

/// What pointing the main account at a folder did (#294).
enum MainFolderResult: Equatable, Sendable {
    /// The main account now reads this scope.
    case moved(CredentialScope)
    /// Nothing changed, for this reason.
    case refused(AccountConnectResult)
}

// MARK: - Health

/// Where one Claude account stands, in the terms Settings shows it. Worked
/// out from what the account's store and token provider already know; it
/// never depends on `hasConfig`, which only says a token was read once.
enum AccountHealth: Equatable, Sendable {
    /// Started, nothing back yet.
    case checking
    case upToDate(Date)
    /// Not tracked for now: no read, no call. The last numbers stay, dated.
    case paused(lastUpdate: Date?)
    /// A login exists and Anthropic refuses it. TokenEater never renews a
    /// login (#268): the user reopens Claude Code on the folder.
    case loginExpired(since: Date?, command: String)
    case accessDenied
    case timedOut
    /// Nothing to read for this exact folder.
    case noLogin(command: String)
    case folderMissing
    case rateLimited
    case network
    /// Two or more accounts: the login's profile could not be fetched yet,
    /// so nothing is written until it is.
    case identityPending
    /// The login no longer belongs to this account. `otherName` names the
    /// tracked account it belongs to; `source` says where the main account's
    /// token came from, since that is what moved.
    case identityConflict(IdentityVerdict, otherName: String?, source: TokenSource?)

    static func resolve(
        errorState: AppErrorState,
        diagnostic: TokenDiagnostic,
        loginExpiredSince: Date?,
        identityState: IdentityState,
        isPaused: Bool,
        lastUpdate: Date?,
        folderExists: Bool,
        command: String,
        names: [AccountID: String]
    ) -> AccountHealth {
        if isPaused { return .paused(lastUpdate: lastUpdate) }
        if !folderExists { return .folderMissing }
        if case .conflict(let verdict) = identityState {
            var other: String?
            if case .belongsTo(let id) = verdict { other = names[id] }
            return .identityConflict(verdict, otherName: other, source: diagnostic.source)
        }
        switch errorState {
        case .tokenUnavailable:
            // A token read from a file while the live Keychain item was
            // refused is the Keychain's problem, not an expired login (#273).
            if diagnostic.source == nil || diagnostic.isStaleFallback {
                switch diagnostic.keychainFailure {
                case .accessDenied: return .accessDenied
                case .timedOut: return .timedOut
                default:
                    if diagnostic.source == nil { return .noLogin(command: command) }
                }
            }
            return .loginExpired(since: loginExpiredSince ?? diagnostic.loginExpiresAt, command: command)
        case .rateLimited:
            return .rateLimited
        case .networkError:
            return .network
        case .none:
            break
        }
        if identityState == .pending { return .identityPending }
        guard let lastUpdate else { return .checking }
        return .upToDate(lastUpdate)
    }

    /// Something the user should look at.
    var needsAttention: Bool {
        switch self {
        case .checking, .upToDate, .paused, .identityPending: return false
        default: return true
        }
    }
}

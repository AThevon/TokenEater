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
    static func decode(_ data: Data?, home: String = ClaudeConfigDirResolver.realHome()) -> [ClaudeAccountRecord] {
        var records: [ClaudeAccountRecord] = []
        if let data,
           let decoded = try? JSONDecoder().decode([Lossy<ClaudeAccountRecord>].self, from: data) {
            records = decoded.compactMap(\.value)
        }
        let main = records.first(where: { $0.id.isMain }) ?? .defaultMain()
        var seenIDs: Set<AccountID> = [.main]
        // The main account without a folder of its own reads `~/.claude`, so
        // an added account on that folder would be a second copy of it.
        let mainDir = main.configDir ?? ClaudeConfigDirResolver.defaultDirectory(home: home)
        var seenDirs: Set<String> = [ClaudeConfigDirResolver.normalize(mainDir, home: home)]
        var result = [main]
        for record in records where !record.id.isMain {
            // An added account always has a folder of its own: without one it
            // would read the main account's login.
            guard let dir = record.configDir.map({ ClaudeConfigDirResolver.normalize($0, home: home) }),
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

    static func load(
        from defaults: UserDefaults,
        home: String = ClaudeConfigDirResolver.realHome()
    ) -> [ClaudeAccountRecord] {
        decode(defaults.data(forKey: defaultsKey), home: home)
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
/// The presets avoid the greens, ambers, oranges and reds that risk uses,
/// which leaves them a narrow band of the wheel: the menu bar's ring is all
/// that tells two accounts apart there, so a new account gets the preset
/// that reads furthest from every colour already worn (`nextColor`), and
/// the presets are listed in the order that rule hands them out from the
/// main account's blue. The first stays the main account's decoding default.
enum AccountPalette {
    /// The one grey preset, also what a removed account's widget wears.
    static let slate = "#94A3B8"

    static let presets: [String] = [
        "#5B8DEF", // blue
        "#F472B6", // pink
        "#C084FC", // lilac
        "#22D3EE", // cyan
        slate,
        "#8B7CF6", // violet
        "#E879F9", // fuchsia
        "#6366F1", // indigo
    ]

    /// Below this hue distance two identity colours read as one on the menu
    /// bar's ring.
    static let alikeBelow: Double = 30

    /// How far apart two identity colours read, in hue degrees: their hue
    /// distance when both are colourful, nothing between two greys, and
    /// `alikeBelow` between a grey and a colour (told apart, barely). Nil
    /// when either is not a colour.
    static func distance(_ a: String, _ b: String) -> Double? {
        guard let hueA = hue(of: a), let hueB = hue(of: b),
              let chromaA = chroma(of: a), let chromaB = chroma(of: b) else { return nil }
        switch (chromaA >= 0.25, chromaB >= 0.25) {
        case (true, true): return hueDistance(hueA, hueB)
        case (false, false): return 0
        default: return alikeBelow
        }
    }

    /// Whether a colour would pass for one already worn on the menu bar's
    /// ring. A pick that does gets a warning; nothing refuses it.
    static func looksLikeAny(_ hex: String, of others: [String]) -> Bool {
        others.contains { other in
            guard let d = distance(hex, other) else { return false }
            return d < alikeBelow
        }
    }

    /// The red, green and blue of a `#RRGGBB` colour, 0 to 1.
    private static func rgb(of hex: String) -> (r: Double, g: Double, b: Double)? {
        guard let normalized = normalizedHex(hex),
              let value = Int(normalized.dropFirst(), radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    /// How far a colour is from grey, 0 to 1.
    static func chroma(of hex: String) -> Double? {
        guard let (r, g, b) = rgb(of: hex) else { return nil }
        return max(r, g, b) - min(r, g, b)
    }

    /// Whether a colour could pass for one of the risk colours: a hue within
    /// 20 degrees of one of them, both colourful enough for the hue to read.
    /// A custom identity colour that does gets a warning; nothing refuses it.
    static func resemblesRiskColor(_ hex: String, riskColors: [String]) -> Bool {
        guard let hue = hue(of: hex), let chroma = chroma(of: hex), chroma >= 0.25 else { return false }
        return riskColors.contains { risk in
            guard let riskHue = self.hue(of: risk), let riskChroma = self.chroma(of: risk),
                  riskChroma >= 0.25 else { return false }
            return hueDistance(hue, riskHue) < 20
        }
    }

    /// The hue of a `#RRGGBB` colour in degrees, nil when it is not one.
    static func hue(of hex: String) -> Double? {
        guard let (r, g, b) = rgb(of: hex) else { return nil }
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        guard delta > 0 else { return 0 }
        var h: Double
        if maxC == r {
            h = (g - b) / delta
        } else if maxC == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        h *= 60
        return h < 0 ? h + 360 : h
    }

    /// Distance between two hues on the colour wheel, 0 to 180 degrees.
    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    /// The free preset that reads furthest from every colour the tracked
    /// accounts wear (a custom one included), the earlier preset on a tie;
    /// cycling once all eight are taken.
    static func nextColor(excluding used: [String]) -> String {
        let worn = used.compactMap(normalizedHex)
        let taken = Set(worn)
        let free = presets.filter { !taken.contains($0) }
        guard !free.isEmpty else { return presets[taken.count % presets.count] }
        guard !worn.isEmpty else { return free[0] }
        func nearest(_ hex: String) -> Double {
            worn.compactMap { distance(hex, $0) }.min() ?? 180
        }
        var best = free[0]
        var bestDistance = nearest(best)
        for candidate in free.dropFirst() {
            let d = nearest(candidate)
            if d > bestDistance { best = candidate; bestDistance = d }
        }
        return best
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

    /// What a monochrome menu bar writes next to each account's ring, since
    /// every ring there has the same colour: the name's first letter, or its
    /// first two or three when another account's name starts the same way.
    /// Names still alike after three letters ("Work" and "Work 2", or two
    /// that differ only in case) fall back to their first letter and their
    /// rank among those alike, in the order given ("W1", "W2"), so no two
    /// rings ever carry the same text. A colour bar never draws a name; this
    /// is the one place letters stand in for the colour. Pass only the
    /// accounts the bar marks, in the bar's order.
    static func monochromeInitials(_ names: [(key: String, name: String)]) -> [String: String] {
        let longest = 3
        let trimmed = names.map { (key: $0.key, letters: Array($0.name.trimmingCharacters(in: .whitespaces))) }
        var initials: [(key: String, text: String)] = []
        for (key, letters) in trimmed {
            var length = 1
            while length < min(longest, letters.count),
                  trimmed.contains(where: { other in
                      other.key != key && String(other.letters).lowercased()
                          .hasPrefix(String(letters.prefix(length)).lowercased())
                  }) {
                length += 1
            }
            let prefix = String(letters.prefix(length))
            initials.append((key, prefix.prefix(1).uppercased() + prefix.dropFirst()))
        }
        var result: [String: String] = [:]
        var rank: [String: Int] = [:]
        for (key, text) in initials {
            let alike = initials.filter { $0.text.lowercased() == text.lowercased() }
            guard alike.count > 1 else {
                result[key] = text
                continue
            }
            let group = text.lowercased()
            rank[group, default: 0] += 1
            result[key] = text.prefix(1).uppercased() + String(rank[group]!)
        }
        return result
    }
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
    /// The account is no longer tracked (removed while a check was out):
    /// nothing may be written for it.
    case untracked
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

    /// Running Claude accounts from which the switcher folds them into one
    /// Claude pill that opens a list. Two pills of names still fit the
    /// 300-point popover next to All and Codex; a third does not.
    static let claudeMenuThreshold = 3

    /// Whether the Claude accounts of these choices go behind a single pill.
    static func collapsesClaude(_ choices: [ModeChoice]) -> Bool {
        choices.filter { $0.mode == .claude }.count >= claudeMenuThreshold
    }
}

// MARK: - Notifications

/// Which Claude account a notification service speaks for, and how its alerts
/// name it. The main account's scope with nothing to say produces exactly the
/// identifiers, subtitle and thread the app has always used.
///
/// The two closures are read when an alert is built, not when the service is
/// made, so a rename, a second account appearing or the main account moving to
/// another folder (#294) reach the next banner without rebuilding anything.
struct NotificationScope: Sendable {
    let account: AccountID
    /// The account's name, for the subtitle and the body, or nil to keep the
    /// alerts anonymous (a single running account).
    let displayName: @Sendable () -> String?
    /// The command that renews the account's login when it lives in its own
    /// config folder (`CLAUDE_CONFIG_DIR=~/.claude-work claude`), or nil for
    /// `~/.claude`, whose alert says to run `claude`.
    let loginCommand: @Sendable () -> String?

    init(
        account: AccountID,
        displayName: @escaping @Sendable () -> String? = { nil },
        loginCommand: @escaping @Sendable () -> String? = { nil }
    ) {
        self.account = account
        self.displayName = displayName
        self.loginCommand = loginCommand
    }

    static let main = NotificationScope(account: .main)
}

// MARK: - Widget

extension AccountID {
    /// The shared file the account's numbers go to, next to `shared.json` in
    /// the folder the widget reads: `shared.json` itself for the main account,
    /// `shared-acct-<uuid>.json` for an added one. Built only from a validated
    /// identifier, so it never leaves that folder.
    var sharedFileName: String {
        isMain ? "shared.json" : "shared-\(rawValue).json"
    }
}

/// What the sandboxed widget may know about a tracked account, written into
/// `shared.json` (`accountsIndex`) for the account picker of the
/// "Claude · Account" widget: the local identifier, the name the user chose,
/// the colour and whether the account is paused. Never an email, an account
/// or organization uuid, an organization name, a folder or a Keychain
/// service, since everything in that folder is readable by the widget.
struct AccountIndexEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// `AccountID.rawValue`.
    let id: String
    let name: String
    let colorHex: String
    let isPaused: Bool

    init(id: String, name: String, colorHex: String, isPaused: Bool) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isPaused = isPaused
    }

    init(_ record: ClaudeAccountRecord) {
        self.init(
            id: record.id.rawValue,
            name: record.name,
            colorHex: record.colorHex,
            isPaused: record.isPaused
        )
    }

    /// The main account as the widget assumes it while no index was ever
    /// written: one account, under the default name and the first colour.
    /// An install that never adds an account never writes an index, since
    /// this is exactly what it would say.
    static let mainFallback = AccountIndexEntry(ClaudeAccountRecord.defaultMain())

    /// The index for these records, in display order, main first.
    static func index(of records: [ClaudeAccountRecord]) -> [AccountIndexEntry] {
        records.map(AccountIndexEntry.init)
    }

    /// The identifier, when it is one this build would ever have written.
    /// Anything else is never turned into a file name.
    var accountID: AccountID? {
        AccountID.isValid(id) ? AccountID(rawValue: id) : nil
    }

    var isMain: Bool { id == AccountID.main.rawValue }

    /// The index as the widget reads it: the stored one, or the main account
    /// alone when none was written yet.
    static func effectiveIndex(_ stored: [AccountIndexEntry]?) -> [AccountIndexEntry] {
        let valid = (stored ?? []).filter { $0.accountID != nil }
        guard !valid.isEmpty else { return [mainFallback] }
        return valid
    }

    /// The account a widget configured with `id` shows: the main account for
    /// nil (a widget nobody configured), the matching entry otherwise, nil
    /// for an identifier the index does not list any more (a removed account).
    static func resolve(_ id: String?, in index: [AccountIndexEntry]) -> AccountIndexEntry? {
        let entries = effectiveIndex(index)
        guard let id, id != AccountID.main.rawValue else {
            return entries.first(where: \.isMain) ?? mainFallback
        }
        return entries.first { $0.id == id }
    }
}

/// The accounts index as `shared.json` stores it. Decoding never throws,
/// whatever the key holds: an entry this build cannot read is dropped, and a
/// value of another shape reads as an empty index. A malformed index must
/// never cost the widgets the usage stored next to it, which a throwing
/// field would (the whole file fails to decode).
struct StoredAccountsIndex: Codable, Equatable, Sendable {
    var entries: [AccountIndexEntry]

    init(_ entries: [AccountIndexEntry]) {
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let lossy = (try? container.decode([Lossy<AccountIndexEntry>].self)) ?? []
        entries = lossy.compactMap(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries)
    }
}

/// What the "Claude · Account" widget has to show for the account it was
/// configured with.
enum ClaudeAccountEntryState: Equatable, Sendable {
    /// Tracked and running: its numbers, under its name and colour.
    case active(AccountIndexEntry)
    /// Tracked but paused: its last numbers, dimmed and labelled as paused.
    case paused(AccountIndexEntry)
    /// No longer tracked: the widget says so instead of quietly falling back
    /// to another account.
    case removed

    static func resolve(id: String?, index: [AccountIndexEntry]?) -> ClaudeAccountEntryState {
        guard let entry = AccountIndexEntry.resolve(id, in: index ?? []) else { return .removed }
        return entry.isPaused && !entry.isMain ? .paused(entry) : .active(entry)
    }

    var entry: AccountIndexEntry? {
        switch self {
        case .active(let entry), .paused(let entry): return entry
        case .removed: return nil
        }
    }

    /// The shared file holding the account's numbers, nil once it is removed.
    var sharedFileName: String? {
        entry?.accountID?.sharedFileName
    }
}

// MARK: - Resolving an account

extension AccountID {
    /// The account a Claude element or segment reads:
    /// - the one it names, when that account is running;
    /// - nothing when it names one that is paused or removed, so it steps
    ///   aside like a segment of a provider switched off;
    /// - otherwise the account the mode shows: the focused one in Claude
    ///   mode, the main one everywhere else.
    ///
    /// `running` is the main account plus every added account that is not
    /// paused. Codex and neutral kinds never ask.
    static func effective(
        declared: AccountID?,
        mode: ProviderMode,
        focused: AccountID,
        running: Set<AccountID>
    ) -> AccountID? {
        if let declared {
            return declared.isMain || running.contains(declared) ? declared : nil
        }
        if mode == .claude, running.contains(focused) { return focused }
        return .main
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
    /// The main account has a login, but whose it is could not be learned
    /// (expired, rate-limited, offline), so a duplicate of it could not be
    /// ruled out.
    case mainUnidentified
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

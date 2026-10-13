// contract-check: the maintainer's weekly canary for the two usage endpoints.
//
// TokenEater decodes both usage responses tolerantly, so a renamed key or a
// changed type silently empties a card instead of failing. This tool makes
// that loud. Once a week it fetches each live response with the maintainer's
// own login (read only, never refreshed), grades it against the baseline
// committed on main, and on real drift writes the new baseline plus a report
// to the `bot/contract-drift` branch through the GitHub API. A workflow turns
// that push into a PR authored by github-actions[bot]; merging it is the
// acknowledgement. Every run that reaches GitHub also refreshes the
// CONTRACT_CHECK_HEARTBEAT variable that a daily watchdog workflow checks.
//
// It runs locally under launchd because the Claude usage endpoint only
// accepts the Claude Code login (a `claude setup-token` token lacks the
// user:profile scope), and that login cannot be copied to CI without breaking
// the laptop session. See Tools/contract-check/README.md.
//
// Usage:
//   contract-check                 scheduled run: weekly gate, check, publish
//   contract-check --force         same, ignoring the weekly gate
//   contract-check --dry-run [--local DIR] [--save DIR] [--provider claude|codex]
//                                  fetch and grade, print the result, write
//                                  nothing to GitHub or to the local state
//   contract-check --compare BASE LIVE --provider claude|codex [--local DIR]
//                                  grade two signature files offline

import Foundation
import Security

// MARK: - Configuration

let environment = ProcessInfo.processInfo.environment
let repo = environment["CONTRACT_CHECK_REPO"] ?? "AThevon/TokenEater"
let build = environment["CONTRACT_CHECK_BUILD"] ?? "dev"
let toolPath = "Tools/contract-check"
let driftBranch = "bot/contract-drift"
let heartbeatVariable = "CONTRACT_CHECK_HEARTBEAT"
/// Scheduled workflows on a public repo are disabled after 60 days without
/// activity. These two must keep running, so every online run re-enables them.
let watchedWorkflows = ["contract-heartbeat.yml", "contract-upstream.yml"]
/// A week, minus half an hour so the hourly job does not slip by one hour
/// every week.
let checkInterval: TimeInterval = 7 * 86_400 - 1_800
/// The heartbeat is rewritten when a status changes, and at least this often.
let heartbeatInterval: TimeInterval = 86_400
/// A token this close to expiry is treated as expired: no request is made.
let expiryMargin: TimeInterval = 5 * 60

let realHome: String = {
    if let entry = getpwuid(getuid()) { return String(cString: entry.pointee.pw_dir) }
    return NSHomeDirectory()
}()
let supportDirectory = environment["CONTRACT_CHECK_HOME"]
    ?? realHome + "/Library/Application Support/TokenEaterContractCheck"
/// A folder of saved raw responses (`claude-usage.json`, `codex-usage.json`)
/// used instead of the network and the credentials, to rehearse the
/// publishing path against a fork (see the README).
let replayDirectory = environment["CONTRACT_CHECK_REPLAY"]
let statePath = supportDirectory + "/state.json"

enum ProviderID: String, CaseIterable {
    case claude, codex

    var key: String { rawValue + "-usage" }
    var name: String { self == .claude ? "Claude" : "Codex" }
    var baselinePath: String { "\(toolPath)/baselines/\(key).json" }
}

// MARK: - Output

func log(_ message: String) {
    FileHandle.standardError.write(Data("[\(Date().ISO8601Format())] \(message)\n".utf8))
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    log(message)
    exit(code)
}

// MARK: - Options

struct Options {
    var dryRun = false
    var force = false
    var local: String?
    var save: String?
    var compare: (base: String, live: String)?
    var providers = ProviderID.allCases
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    func value(after flag: String) -> String {
        guard !arguments.isEmpty else { fail("\(flag) needs a value", code: 64) }
        return arguments.removeFirst()
    }
    while !arguments.isEmpty {
        let flag = arguments.removeFirst()
        switch flag {
        case "--dry-run": options.dryRun = true
        case "--force": options.force = true
        case "--local": options.local = value(after: flag)
        case "--save": options.save = value(after: flag)
        case "--compare":
            let base = value(after: flag)
            options.compare = (base, value(after: flag))
        case "--provider":
            guard let provider = ProviderID(rawValue: value(after: flag)) else { fail("unknown provider", code: 64) }
            options.providers = [provider]
        default:
            fail("unknown option \(flag); see the header of main.swift", code: 64)
        }
    }
    return options
}

// MARK: - Subprocess

final class Buffer: @unchecked Sendable {
    var data = Data()
}

struct ProcessResult {
    let status: Int32
    let output: Data
    let errorOutput: String
    let timedOut: Bool

    var text: String { String(data: output, encoding: .utf8) ?? "" }
}

/// Runs a binary with a timeout. Both pipes are drained while the process
/// runs, so a large payload cannot fill a pipe and hang it.
func runProcess(_ path: String, _ arguments: [String], input: Data? = nil, timeout: TimeInterval) -> ProcessResult? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    let output = Pipe(), errors = Pipe(), stdin = Pipe()
    task.standardOutput = output
    task.standardError = errors
    task.standardInput = input == nil ? FileHandle.nullDevice : stdin
    do { try task.run() } catch { return nil }

    let out = Buffer(), err = Buffer()
    let drained = DispatchGroup()
    for (pipe, buffer) in [(output, out), (errors, err)] {
        drained.enter()
        DispatchQueue.global().async {
            buffer.data = pipe.fileHandleForReading.readDataToEndOfFile()
            drained.leave()
        }
    }
    if let input {
        DispatchQueue.global().async {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }
    }

    let exited = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        task.waitUntilExit()
        exited.signal()
    }
    var timedOut = false
    if exited.wait(timeout: .now() + timeout) == .timedOut {
        timedOut = true
        task.terminate()
        _ = exited.wait(timeout: .now() + 2)
    }
    _ = drained.wait(timeout: .now() + 2)
    return ProcessResult(status: timedOut ? -1 : task.terminationStatus,
                         output: out.data,
                         errorOutput: String(data: err.data, encoding: .utf8) ?? "",
                         timedOut: timedOut)
}

// MARK: - Credentials

struct Credential {
    let token: String
    let accountID: String?
    let expiresAt: Date?
    let source: String

    var isFresh: Bool { expiresAt.map { $0.timeIntervalSinceNow > expiryMargin } ?? true }
}

enum CredentialLookup {
    case usable(Credential)
    /// A login exists but every token in reach has expired. Waiting for the
    /// user to open the client is the only remedy: nothing here refreshes.
    case expired(Date?)
    case missing(String)
}

/// Claude Code writes `expiresAt` in milliseconds; seconds are accepted too,
/// exactly like the app's SecurityCLIReader.
func claudeExpiry(_ value: Any?) -> Date? {
    let raw: Double
    switch value {
    case let number as NSNumber: raw = number.doubleValue
    case let string as String: guard let parsed = Double(string) else { return nil }; raw = parsed
    default: return nil
    }
    guard raw > 0 else { return nil }
    return Date(timeIntervalSince1970: raw > 1_000_000_000_000 ? raw / 1000 : raw)
}

func claudeCredential(fromJSON data: Data, source: String) -> Credential? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = root["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
    return Credential(token: token, accountID: nil, expiresAt: claudeExpiry(oauth["expiresAt"]), source: source)
}

/// Account names under the Claude Code service, attributes only: the ACL
/// guards the payload, not the item's existence, so this never prompts.
func keychainAccounts(service: String) -> [String] {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecReturnAttributes as String: true,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let items = result as? [[String: Any]] else { return [] }
    return items.compactMap { $0[kSecAttrAccount as String] as? String }
}

/// The app's primary source, ported: `/usr/bin/security` for each item that
/// shares the service name (#268), keeping the login that lasts longest.
func keychainCredential(notes: inout [String]) -> Credential? {
    let service = "Claude Code-credentials"
    let accounts = keychainAccounts(service: service)
    let targets: [String?] = accounts.count > 1 ? accounts.map { Optional($0) } : [accounts.first]
    var found: [Credential] = []
    for account in targets {
        var arguments = ["find-generic-password", "-s", service]
        if let account { arguments += ["-a", account] }
        arguments.append("-w")
        guard let result = runProcess("/usr/bin/security", arguments, timeout: 5) else {
            notes.append("keychain: security could not launch")
            continue
        }
        switch (result.timedOut, result.status) {
        case (true, _): notes.append("keychain: timed out")
        case (_, 0):
            if let credential = claudeCredential(fromJSON: result.output, source: "keychain") {
                found.append(credential)
            } else {
                notes.append("keychain: item holds no Claude Code login")
            }
        case (_, 44): notes.append("keychain: not found")
        case (_, 45): notes.append("keychain: access denied")
        default: notes.append("keychain: security exited \(result.status)")
        }
    }
    return found.max { ($0.expiresAt ?? .distantPast) < ($1.expiresAt ?? .distantPast) }
}

/// Same order as the app: the Keychain, then `~/.claude/.credentials.json`.
/// The first token that is not expired wins.
func claudeLookup() -> CredentialLookup {
    var notes: [String] = []
    var candidates: [Credential] = []
    if let credential = keychainCredential(notes: &notes) { candidates.append(credential) }
    let file = realHome + "/.claude/.credentials.json"
    if let data = FileManager.default.contents(atPath: file),
       let credential = claudeCredential(fromJSON: data, source: "credentials file") {
        candidates.append(credential)
    }
    if let fresh = candidates.first(where: \.isFresh) { return .usable(fresh) }
    if !candidates.isEmpty { return .expired(candidates.compactMap(\.expiresAt).max()) }
    return .missing(notes.isEmpty ? "no Claude Code login found" : notes.joined(separator: "; "))
}

/// The `exp` claim of a JWT, read without verifying anything.
func jwtExpiry(_ token: String) -> Date? {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard let data = Data(base64Encoded: payload),
          let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let exp = claims["exp"] as? NSNumber else { return nil }
    return Date(timeIntervalSince1970: exp.doubleValue)
}

/// `~/.codex/auth.json` (or `$CODEX_HOME`), file-backed ChatGPT logins only,
/// like CodexAuthReader. The refresh token is never read.
func codexLookup() -> CredentialLookup {
    let home = environment["CODEX_HOME"].map { ($0 as NSString).expandingTildeInPath } ?? realHome + "/.codex"
    guard let data = FileManager.default.contents(atPath: home + "/auth.json"),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return .missing("no-login")
    }
    if let mode = (root["auth_mode"] as? String)?.lowercased(), !["chatgpt", "chatgptauthtokens"].contains(mode) {
        return .missing("no-login (auth_mode \(mode))")
    }
    let tokens = root["tokens"] as? [String: Any]
    guard let token = tokens?["access_token"] as? String, !token.isEmpty else { return .missing("no-login") }
    let credential = Credential(token: token, accountID: tokens?["account_id"] as? String,
                                expiresAt: jwtExpiry(token), source: "auth.json")
    return credential.isFresh ? .usable(credential) : .expired(credential.expiresAt)
}

// MARK: - Fetch

/// The newest Claude Code installed, for the same User-Agent the app sends.
func claudeCodeVersion() -> String {
    let directories = [
        realHome + "/.local/share/claude/versions",
        realHome + "/Library/Application Support/Claude/claude-code",
        "/opt/homebrew/Caskroom/claude-code", "/usr/local/Caskroom/claude-code",
        "/opt/homebrew/Caskroom/claude-code@latest", "/usr/local/Caskroom/claude-code@latest",
    ]
    let versions = directories.flatMap { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }
        .filter { $0.first?.isNumber == true }
        .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    return versions.last ?? "0.0.0"
}

func request(for provider: ProviderID, credential: Credential) -> URLRequest {
    switch provider {
    case .claude:
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 30
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/\(claudeCodeVersion())", forHTTPHeaderField: "User-Agent")
        return request
    case .codex:
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        if let account = credential.accountID, !account.isEmpty {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TokenEater-contract-check", forHTTPHeaderField: "User-Agent")
        return request
    }
}

enum FetchOutcome {
    case ok([String: Any])
    /// `transient` failures are retried next hour; the others are real errors.
    case failed(status: String, transient: Bool)
}

func fetch(_ request: URLRequest) async -> FetchOutcome {
    let session = URLSession(configuration: .ephemeral)
    let data: Data, response: URLResponse
    do {
        (data, response) = try await session.data(for: request)
    } catch {
        return .failed(status: "network", transient: true)
    }
    guard let http = response as? HTTPURLResponse else { return .failed(status: "invalid-response", transient: false) }
    switch http.statusCode {
    case 200:
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed(status: "not-a-json-object", transient: false)
        }
        return .ok(root)
    case 401, 403: return .failed(status: "unauthorized-\(http.statusCode)", transient: true)
    case 429: return .failed(status: "rate-limited", transient: true)
    case 500..<600: return .failed(status: "http-\(http.statusCode)", transient: true)
    default: return .failed(status: "http-\(http.statusCode)", transient: false)
    }
}

struct Capture {
    let status: String
    let signature: ContractCheck.Signature?
    /// A failure that needs a human, as opposed to "waiting for a fresh token".
    let isError: Bool
}

func lookup(_ provider: ProviderID) -> CredentialLookup {
    if let replayDirectory {
        let exists = FileManager.default.fileExists(atPath: "\(replayDirectory)/\(provider.key).json")
        return exists ? .usable(Credential(token: "", accountID: nil, expiresAt: nil, source: "replay")) : .missing("no replay file")
    }
    return provider == .claude ? claudeLookup() : codexLookup()
}

/// The status of a lookup that leads to no request, nil when a token is usable.
func offlineStatus(_ provider: ProviderID, _ lookup: CredentialLookup) -> String? {
    switch lookup {
    case .missing(let reason):
        return provider == .codex ? "no-login" : "no-login: \(reason)"
    case .expired(let date):
        return "token-expired" + (date.map { " since \($0.ISO8601Format())" } ?? "")
    case .usable:
        return nil
    }
}

/// Fetches and reduces one response. The credential lookup is separate so a
/// scheduled run can stay offline while no token is usable.
func capture(_ provider: ProviderID, lookup: CredentialLookup, readSet: ContractCheck.Provider,
             baseline: ContractCheck.Signature?) async -> Capture {
    guard case .usable(let credential) = lookup else {
        return Capture(status: offlineStatus(provider, lookup) ?? "", signature: nil, isError: false)
    }
    let outcome: FetchOutcome
    if let replayDirectory {
        let data = FileManager.default.contents(atPath: "\(replayDirectory)/\(provider.key).json") ?? Data()
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        outcome = root.map(FetchOutcome.ok) ?? .failed(status: "not-a-json-object", transient: false)
    } else {
        outcome = await fetch(request(for: provider, credential: credential))
    }
    switch outcome {
    case .failed(let status, let transient):
        return Capture(status: status, signature: nil, isError: !transient)
    case .ok(let root):
        let signature = ContractCheck.signature(of: root, provider: readSet, baseline: baseline)
        return Capture(status: "ok", signature: signature, isError: false)
    }
}

// MARK: - GitHub

struct GitHubError: Error, CustomStringConvertible {
    let description: String
    var isNotFound: Bool { description.contains("HTTP 404") }
}

/// Everything goes through `gh`, already authenticated as the maintainer. No
/// git command ever runs, so no worktree is touched.
struct GitHub {
    let gh: String

    static func locate() -> GitHub? {
        var candidates: [String] = []
        if let baked = environment["GH_BIN"] { candidates.append(baked) }
        candidates += (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/gh" }
        candidates += [realHome + "/.nix-profile/bin/gh", "/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(GitHub.init)
    }

    @discardableResult
    func run(_ arguments: [String], input: Data? = nil) throws -> Data {
        guard let result = runProcess(gh, arguments, input: input, timeout: 60) else {
            throw GitHubError(description: "gh could not launch")
        }
        guard !result.timedOut else { throw GitHubError(description: "gh \(arguments.prefix(2).joined(separator: " ")) timed out") }
        guard result.status == 0 else {
            throw GitHubError(description: result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.output
    }

    func api(_ endpoint: String, method: String = "GET", body: [String: Any]? = nil) throws -> [String: Any] {
        var arguments = ["api", "-X", method, endpoint]
        var input: Data?
        if let body {
            arguments += ["--input", "-"]
            input = try JSONSerialization.data(withJSONObject: body)
        }
        let data = try run(arguments, input: input)
        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// A file's raw bytes at a ref, nil when it does not exist there.
    func file(_ path: String, ref: String) throws -> Data? {
        do {
            return try run(["api", "-H", "Accept: application/vnd.github.raw+json", "repos/\(repo)/contents/\(path)?ref=\(ref)"])
        } catch let error as GitHubError where error.isNotFound {
            return nil
        }
    }

    func branchHead(_ branch: String) throws -> String? {
        do {
            let ref = try api("repos/\(repo)/git/ref/heads/\(branch)")
            return (ref["object"] as? [String: Any])?["sha"] as? String
        } catch let error as GitHubError where error.isNotFound {
            return nil
        }
    }

    func hasOpenPullRequest(head: String) throws -> Bool {
        let data = try run(["pr", "list", "--repo", repo, "--head", head, "--state", "open", "--json", "number"])
        return ((try? JSONSerialization.jsonObject(with: data) as? [Any]) ?? []).isEmpty == false
    }

    func deleteBranch(_ branch: String) throws {
        _ = try api("repos/\(repo)/git/refs/heads/\(branch)", method: "DELETE")
    }

    /// One commit on top of `parent` through the Git Data API, then the branch
    /// moved (or created) to it. Never a force update.
    func commit(_ files: [String: String], message: String, parent: String, to branch: String, create: Bool) throws {
        let parentCommit = try api("repos/\(repo)/git/commits/\(parent)")
        guard let baseTree = (parentCommit["tree"] as? [String: Any])?["sha"] as? String else {
            throw GitHubError(description: "no tree on commit \(parent)")
        }
        let entries = files.keys.sorted().map { ["path": $0, "mode": "100644", "type": "blob", "content": files[$0]!] }
        let tree = try api("repos/\(repo)/git/trees", method: "POST", body: ["base_tree": baseTree, "tree": entries])
        guard let treeSHA = tree["sha"] as? String else { throw GitHubError(description: "tree creation returned no sha") }
        let commit = try api("repos/\(repo)/git/commits", method: "POST",
                             body: ["message": message, "tree": treeSHA, "parents": [parent]])
        guard let commitSHA = commit["sha"] as? String else { throw GitHubError(description: "commit creation returned no sha") }
        if create {
            _ = try api("repos/\(repo)/git/refs", method: "POST", body: ["ref": "refs/heads/\(branch)", "sha": commitSHA])
        } else {
            _ = try api("repos/\(repo)/git/refs/heads/\(branch)", method: "PATCH", body: ["sha": commitSHA, "force": false])
        }
    }

    /// Turns a watchdog workflow back on when GitHub disabled it for
    /// inactivity. Returns true when it had to.
    func reenableIfDisabled(_ workflow: String) throws -> Bool {
        do {
            let state = try api("repos/\(repo)/actions/workflows/\(workflow)")["state"] as? String
            guard state == "disabled_inactivity" else { return false }
        } catch let error as GitHubError where error.isNotFound {
            return false // not merged yet
        }
        _ = try api("repos/\(repo)/actions/workflows/\(workflow)/enable", method: "PUT")
        return true
    }

    func setVariable(_ name: String, to value: String) throws {
        try run(["variable", "set", name, "--repo", repo, "--body", value])
    }
}

// MARK: - Contract inputs

struct Inputs {
    let mainSHA: String?
    let readSet: ContractCheck.ReadSet
    let baselines: [ProviderID: ContractCheck.Signature]
}

func decodeBaseline(_ data: Data?, _ provider: ProviderID) throws -> ContractCheck.Signature? {
    guard let data else { return nil }
    do {
        return try ContractCheck.decodeSignature(data)
    } catch {
        throw GitHubError(description: "\(provider.baselinePath) is not a v2 signature: \(error)")
    }
}

/// The read set and baselines as committed on main, read through the API so a
/// stale or switched local checkout never matters.
func remoteInputs(_ github: GitHub) throws -> Inputs {
    guard let main = try github.branchHead("main") else { throw GitHubError(description: "main not found") }
    guard let readSetData = try github.file("\(toolPath)/read-set.json", ref: main) else {
        throw GitHubError(description: "\(toolPath)/read-set.json is not on main")
    }
    var baselines: [ProviderID: ContractCheck.Signature] = [:]
    for provider in ProviderID.allCases {
        baselines[provider] = try decodeBaseline(github.file(provider.baselinePath, ref: main), provider)
    }
    return Inputs(mainSHA: main, readSet: try ContractCheck.decodeReadSet(readSetData), baselines: baselines)
}

/// The same inputs from a checkout's Tools/contract-check folder (dry runs).
func localInputs(_ directory: String) throws -> Inputs {
    let root = URL(fileURLWithPath: directory)
    let readSet = try ContractCheck.decodeReadSet(Data(contentsOf: root.appendingPathComponent("read-set.json")))
    var baselines: [ProviderID: ContractCheck.Signature] = [:]
    for provider in ProviderID.allCases {
        let url = root.appendingPathComponent("baselines/\(provider.key).json")
        baselines[provider] = try decodeBaseline(try? Data(contentsOf: url), provider)
    }
    return Inputs(mainSHA: nil, readSet: readSet, baselines: baselines)
}

func readSetProvider(_ inputs: Inputs, _ provider: ProviderID) -> ContractCheck.Provider {
    guard let entry = inputs.readSet.providers[provider.key] else {
        fail("read-set.json has no \(provider.key) provider")
    }
    return entry
}

// MARK: - Publishing

/// Writes the new baselines and the report to the drift branch. The branch is
/// left alone when it already carries exactly these baselines, which is what
/// keeps an unacknowledged drift from being re-pushed every week.
func publishDrift(_ github: GitHub, inputs: Inputs, observed: [ProviderID: ContractCheck.Signature]) throws -> Bool {
    guard let mainSHA = inputs.mainSHA else { return false }

    var parent = mainSHA
    var create = true
    var pending: [ProviderID: ContractCheck.Signature] = [:]
    if let head = try github.branchHead(driftBranch) {
        if try github.hasOpenPullRequest(head: driftBranch) {
            parent = head
            create = false
            for provider in ProviderID.allCases {
                pending[provider] = try decodeBaseline(github.file(provider.baselinePath, ref: head), provider)
            }
        } else {
            // Left over from a merged or closed PR: start again from main.
            try github.deleteBranch(driftBranch)
        }
    }

    var files: [String: String] = [:]
    var reports: [ContractCheck.ProviderReport] = []
    for provider in ProviderID.allCases {
        let readSet = readSetProvider(inputs, provider)
        let main = inputs.baselines[provider]
        guard observed[provider] != nil || pending[provider] != nil else { continue }
        var next = main ?? ContractCheck.Signature(endpoint: readSet.endpoint)
        if let prior = pending[provider] { next = ContractCheck.merge(next, prior) }
        if let live = observed[provider] { next = ContractCheck.merge(next, live) }
        let changes = ContractCheck.diff(baseline: main, live: next, provider: readSet)
        guard !changes.isEmpty else { continue }
        reports.append(.init(name: provider.name, endpoint: readSet.endpoint, changes: changes))
        if next != pending[provider] { files[provider.baselinePath] = ContractCheck.encode(next) }
    }
    guard !files.isEmpty else {
        log("Drift already pending on \(driftBranch); nothing new to push.")
        return false
    }

    let highest = reports.compactMap(\.highest).max() ?? .active
    files["\(toolPath)/reports/latest-drift.md"] = ContractCheck.report(
        reports, capturedAt: Date().ISO8601Format(), tool: build)
    let message = "chore(contract): record \(highest.label) usage API drift\n\n"
        + reports.map { "\($0.name): \($0.count(.breaking)) breaking, \($0.count(.active)) active, \($0.count(.dormant)) dormant" }
            .joined(separator: "\n")
    try github.commit(files, message: message, parent: parent, to: driftBranch, create: create)
    log("Pushed \(highest.label) drift to \(driftBranch).")
    return true
}

// MARK: - Local state

struct LocalState: Codable {
    var lastOk: [String: Date] = [:]
    var status: [String: String] = [:]
    var heartbeatAt: Date?
    var heartbeat: String?
}

func loadState() -> LocalState {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let data = FileManager.default.contents(atPath: statePath),
          let state = try? decoder.decode(LocalState.self, from: data) else { return LocalState() }
    return state
}

func saveState(_ state: LocalState) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? FileManager.default.createDirectory(atPath: supportDirectory, withIntermediateDirectories: true)
    if let data = try? encoder.encode(state) { FileManager.default.createFile(atPath: statePath, contents: data) }
}

/// What the watchdog workflow reads. Statuses and dates only. `at` is left
/// out when comparing two bodies, or every run would look like a change.
func heartbeatBody(_ state: LocalState, pending: [ContractCheck.Severity: Int], at: Date?) -> String {
    func date(_ provider: ProviderID) -> Any { state.lastOk[provider.rawValue].map { $0.ISO8601Format() } ?? NSNull() }
    var body: [String: Any] = [
        "v": 1,
        "lastOk": Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0.rawValue, date($0)) }),
        "status": state.status,
        "pending": Dictionary(uniqueKeysWithValues: ContractCheck.Severity.allCases.map { ($0.label, pending[$0] ?? 0) }),
        "build": build,
    ]
    if let at { body["at"] = at.ISO8601Format() }
    let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    return String(data: data, encoding: .utf8) ?? "{}"
}

// MARK: - Modes

func printChanges(_ provider: ProviderID, _ changes: [ContractCheck.Change]) {
    print("\n== \(provider.name): \(changes.isEmpty ? "no drift" : "\(changes.count) change(s)")")
    for change in changes.sorted(by: { $0.severity > $1.severity }) {
        print("  \(change.severity.label.uppercased().padding(toLength: 9, withPad: " ", startingAt: 0)) \(change.summary)")
    }
}

func runCompare(_ options: Options, base: String, live: String) throws {
    guard options.providers.count == 1, let provider = options.providers.first else {
        fail("--compare needs --provider", code: 64)
    }
    let inputs = try localInputs(options.local ?? toolPath)
    let readSet = readSetProvider(inputs, provider)
    let baseline = try ContractCheck.decodeSignature(Data(contentsOf: URL(fileURLWithPath: base)))
    let observed = try ContractCheck.decodeSignature(Data(contentsOf: URL(fileURLWithPath: live)))
    let changes = ContractCheck.diff(baseline: baseline, live: observed, provider: readSet)
    printChanges(provider, changes)
}

func runDry(_ options: Options) async throws {
    let inputs: Inputs
    if let local = options.local {
        inputs = try localInputs(local)
    } else {
        guard let github = GitHub.locate() else { fail("gh not found; pass --local Tools/contract-check") }
        inputs = try remoteInputs(github)
    }
    var reports: [ContractCheck.ProviderReport] = []
    for provider in options.providers {
        let readSet = readSetProvider(inputs, provider)
        let baseline = inputs.baselines[provider]
        let result = await capture(provider, lookup: lookup(provider), readSet: readSet, baseline: baseline)
        print("\(provider.name): \(result.status)")
        guard let live = result.signature else { continue }
        let changes = ContractCheck.diff(baseline: baseline, live: live, provider: readSet)
        printChanges(provider, changes)
        if !changes.isEmpty { reports.append(.init(name: provider.name, endpoint: readSet.endpoint, changes: changes)) }
        if let save = options.save {
            try FileManager.default.createDirectory(atPath: save, withIntermediateDirectories: true)
            let path = save + "/\(provider.key).json"
            try ContractCheck.encode(live).write(toFile: path, atomically: true, encoding: .utf8)
            print("Saved the live signature to \(path)")
        }
    }
    if !reports.isEmpty {
        print("\n----- report that a scheduled run would publish -----\n")
        print(ContractCheck.report(reports, capturedAt: Date().ISO8601Format(), tool: build))
    }
}

func runScheduled(_ options: Options) async -> Int32 {
    var state = loadState()
    let now = Date()
    let due = state.lastOk[ProviderID.claude.rawValue].map { now.timeIntervalSince($0) >= checkInterval } ?? true
    // The weekly gate. Silent on purpose: this runs every hour.
    guard due || options.force else { return 0 }

    var exitCode: Int32 = 0
    var observed: [ProviderID: ContractCheck.Signature] = [:]
    var pending: [ContractCheck.Severity: Int] = [:]
    var github: GitHub?
    let lookups = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, lookup($0)) })
    let online = lookups.values.contains { if case .usable = $0 { return true } else { return false } }

    if online {
        guard let located = GitHub.locate() else {
            log("gh not found (GH_BIN, PATH, ~/.nix-profile/bin). Reinstall with install.sh.")
            return 1
        }
        github = located
        let inputs: Inputs
        do {
            inputs = try remoteInputs(located)
        } catch {
            log("Could not read the contract inputs from main: \(error)")
            return 1
        }

        var shouldPublish = false
        for provider in ProviderID.allCases {
            let readSet = readSetProvider(inputs, provider)
            let baseline = inputs.baselines[provider]
            let result = await capture(provider, lookup: lookups[provider]!, readSet: readSet, baseline: baseline)
            // The "error: " prefix is what the watchdog keys on to open an
            // issue right away instead of waiting for the heartbeat to age.
            state.status[provider.rawValue] = result.isError ? "error: \(result.status)" : result.status
            if result.isError { exitCode = 1 }
            log("\(provider.name): \(result.status)")
            guard let live = result.signature else { continue }
            observed[provider] = live
            let changes = ContractCheck.diff(baseline: baseline, live: live, provider: readSet)
            for change in changes { pending[change.severity, default: 0] += 1 }
            if changes.contains(where: { $0.severity >= .active }) { shouldPublish = true }
            log("\(provider.name): " + ContractCheck.Severity.allCases.reversed()
                .map { severity in "\(changes.filter { $0.severity == severity }.count) \(severity.label)" }
                .joined(separator: ", "))
        }

        var published = true
        if shouldPublish {
            do {
                _ = try publishDrift(located, inputs: inputs, observed: observed)
            } catch {
                log("Could not publish the drift: \(error)")
                published = false
                exitCode = 1
            }
        }
        // Only a check whose outcome reached GitHub counts. A failed push is
        // retried next hour instead of waiting a week.
        if published {
            for provider in observed.keys { state.lastOk[provider.rawValue] = now }
        }
    } else {
        for (provider, lookup) in lookups {
            state.status[provider.rawValue] = offlineStatus(provider, lookup)
        }
    }

    // The heartbeat goes out when something changed, and once a day while
    // waiting for a token, so the watchdog can tell "waiting" from "dead".
    let core = heartbeatBody(state, pending: pending, at: nil)
    let stale = state.heartbeatAt.map { now.timeIntervalSince($0) >= heartbeatInterval } ?? true
    guard core != state.heartbeat || stale else {
        saveState(state)
        return exitCode
    }
    guard let github = github ?? GitHub.locate() else {
        log("gh not found (GH_BIN, PATH, ~/.nix-profile/bin). Reinstall with install.sh.")
        saveState(state)
        return 1
    }
    for workflow in watchedWorkflows {
        do {
            if try github.reenableIfDisabled(workflow) { log("Re-enabled \(workflow), GitHub had disabled it for inactivity.") }
        } catch {
            log("Could not check \(workflow): \(error)")
            exitCode = 1
        }
    }
    do {
        try github.setVariable(heartbeatVariable, to: heartbeatBody(state, pending: pending, at: now))
        state.heartbeat = core
        state.heartbeatAt = now
    } catch {
        log("Could not write the \(heartbeatVariable) variable: \(error)")
        exitCode = 1
    }
    saveState(state)
    return exitCode
}

// MARK: - Main

let options = parseOptions()
do {
    if let compare = options.compare {
        try runCompare(options, base: compare.base, live: compare.live)
        exit(0)
    }
    if options.dryRun {
        try await runDry(options)
        exit(0)
    }
} catch {
    fail("\(error)")
}
exit(await runScheduled(options))

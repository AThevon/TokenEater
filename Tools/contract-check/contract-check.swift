#!/usr/bin/env swift
//
// contract-check.swift
//
// Maintainer canary for the Anthropic usage API contract.
//
// TokenEater decodes `/api/oauth/usage` tolerantly (every field is `try?`, so a
// renamed or removed key silently becomes `nil` and a card just goes empty).
// That robustness hides upstream contract changes. This tool makes them loud:
// it fetches the live response, reduces it to a value-free shape signature, and
// compares that against a committed baseline. On a meaningful change it opens
// (or comments on) a GitHub issue so the drift is caught in minutes instead of
// via a user bug report.
//
// It runs LOCALLY on the maintainer's machine, never in CI: the endpoint needs
// the personal OAuth token, which Claude Code keeps refreshed on disk. Reading
// that refreshed token locally is trivial; shipping a rotating personal token
// into CI secrets would be fragile and a security smell.
//
// Usage:
//   run.sh                 fetch, compare, open/comment an issue on drift
//   run.sh --dry-run       fetch, compare, print the report; touch nothing else
//   run.sh --update-baseline   capture the current shape as the new baseline
//   run.sh --print         fetch and print the current shape signature
//
// The signature never contains utilization values. It does contain field, kind
// and model names, which can be unreleased Anthropic API codenames, so the full
// signature and the exact names stay LOCAL (baseline file + the launchd log). The
// public GitHub issue only ever gets a redacted, name-free category summary.

import Foundation

// MARK: - Paths

let baselineURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("contract-baseline.json")

let realHome: String = {
    if let pw = getpwuid(getuid()) { return String(cString: pw.pointee.pw_dir) }
    return NSHomeDirectory()
}()

let stateDir = URL(fileURLWithPath: realHome)
    .appendingPathComponent(".tokeneater-contract-check")
let stateURL = stateDir.appendingPathComponent("last-drift.txt")

let repo = "AThevon/TokenEater"
let issueTitle = "Usage API contract drift detected"
let issueLabel = "contract-drift"

// MARK: - CLI flags

let args = Set(CommandLine.arguments.dropFirst())
let dryRun = args.contains("--dry-run")
let updateBaseline = args.contains("--update-baseline")
let printOnly = args.contains("--print")

// MARK: - Small helpers

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Runs a subprocess with a timeout. Returns (status, stdout, stderr) or nil if
/// the binary could not be launched or the call timed out.
@discardableResult
func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 20) -> (Int32, String, String)? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    let out = Pipe(), err = Pipe()
    task.standardOutput = out
    task.standardError = err
    do { try task.run() } catch { return nil }

    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { task.waitUntilExit(); done.signal() }
    if done.wait(timeout: .now() + timeout) == .timedOut {
        task.terminate()
        return nil
    }
    let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (task.terminationStatus, o, e)
}

// MARK: - Token (same sources as the app)

func extractAccessToken(fromJSON raw: String) -> String? {
    guard let data = raw.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = obj["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String,
          !token.isEmpty else { return nil }
    return token
}

func readToken() -> String? {
    // 1. Credentials file (silent, preferred for a background job).
    let credPath = realHome + "/.claude/.credentials.json"
    if let data = FileManager.default.contents(atPath: credPath),
       let raw = String(data: data, encoding: .utf8),
       let token = extractAccessToken(fromJSON: raw) {
        return token
    }
    // 2. Keychain via /usr/bin/security (needs a one-time "Always Allow").
    if let (status, out, _) = run("/usr/bin/security",
                                  ["find-generic-password", "-s", "Claude Code-credentials", "-w"],
                                  timeout: 5),
       status == 0 {
        return extractAccessToken(fromJSON: out.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
}

// MARK: - Fetch

enum FetchResult {
    case ok(Data)
    case skip(String)   // reason (token expired, rate limited, network, ...)
}

func fetchUsage(token: String) -> FetchResult {
    var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    request.httpMethod = "GET"
    request.timeoutInterval = 30
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    // Mirror the app's User-Agent prefix so the endpoint treats us identically.
    request.setValue("claude-code/1.0.0", forHTTPHeaderField: "User-Agent")

    var result: FetchResult = .skip("no response")
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { sem.signal() }
        if let error { result = .skip("network: \(error.localizedDescription)"); return }
        guard let http = response as? HTTPURLResponse else { result = .skip("invalid response"); return }
        switch http.statusCode {
        case 200: result = data.map(FetchResult.ok) ?? .skip("empty body")
        case 401, 403: result = .skip("token expired (HTTP \(http.statusCode))")
        case 429: result = .skip("rate limited (HTTP 429)")
        default: result = .skip("HTTP \(http.statusCode)")
        }
    }.resume()
    if sem.wait(timeout: .now() + 35) == .timedOut { return .skip("request timed out") }
    return result
}

// MARK: - Shape signature

func jsonType(_ value: Any) -> String {
    if value is NSNull { return "null" }
    if let n = value as? NSNumber {
        return CFGetTypeID(n) == CFBooleanGetTypeID() ? "bool" : "number"
    }
    if value is String { return "string" }
    if value is [Any] { return "array" }
    if value is [String: Any] { return "object" }
    return "unknown"
}

struct Signature: Codable, Equatable {
    var topLevelKeys: [String] = []
    var topLevelTypes: [String: String] = [:]
    var objectFieldKeys: [String: [String]] = [:]   // top-level object key -> its nested key list
    var limitsPresent = false
    var limitsEntryKeys: [String] = []
    var limitsKinds: [String] = []
    var limitsGroups: [String] = []
    var limitsModelNames: [String] = []             // reference only; never triggers on its own
}

func buildSignature(from data: Data) -> Signature? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    var sig = Signature()
    sig.topLevelKeys = root.keys.sorted()
    for (k, v) in root {
        sig.topLevelTypes[k] = jsonType(v)
        if let obj = v as? [String: Any] {
            sig.objectFieldKeys[k] = obj.keys.sorted()
        }
    }
    if let limits = root["limits"] as? [[String: Any]] {
        sig.limitsPresent = true
        var entryKeys = Set<String>(), kinds = Set<String>(), groups = Set<String>(), models = Set<String>()
        for entry in limits {
            entry.keys.forEach { entryKeys.insert($0) }
            if let kind = entry["kind"] as? String { kinds.insert(kind) }
            if let group = entry["group"] as? String { groups.insert(group) }
            if let scope = entry["scope"] as? [String: Any],
               let model = scope["model"] as? [String: Any],
               let name = model["display_name"] as? String { models.insert(name) }
        }
        sig.limitsEntryKeys = entryKeys.sorted()
        sig.limitsKinds = kinds.sorted()
        sig.limitsGroups = groups.sorted()
        sig.limitsModelNames = models.sorted()
    }
    return sig
}

// MARK: - Diff

/// One detected change. `category` is a generic, safe-to-publish label; `detail`
/// is the specific field/kind/model name, which can be an unreleased Anthropic
/// codename and is therefore kept local (baseline + logs), never posted to GitHub.
struct Change {
    let category: String
    let detail: String?
    var full: String { detail.map { "\(category): `\($0)`" } ?? category }
}

struct Diff {
    var breaking: [Change] = []
    var additive: [Change] = []
    var notes: [Change] = []   // informational only; does not trigger an issue

    var triggers: Bool { !breaking.isEmpty || !additive.isEmpty }
    /// Stable key (with names) used to avoid re-notifying the same drift daily.
    var dedupKey: String { (breaking + additive).map(\.full).sorted().joined(separator: "\n") }
}

func diff(baseline b: Signature, live l: Signature) -> Diff {
    var d = Diff()
    func setDiff(_ base: [String], _ live: [String]) -> (removed: [String], added: [String]) {
        let bs = Set(base), ls = Set(live)
        return (bs.subtracting(ls).sorted(), ls.subtracting(bs).sorted())
    }

    let tl = setDiff(b.topLevelKeys, l.topLevelKeys)
    tl.removed.forEach { d.breaking.append(Change(category: "Top-level key removed", detail: $0)) }
    tl.added.forEach { d.additive.append(Change(category: "New top-level key", detail: $0)) }

    for (k, bt) in b.topLevelTypes {
        guard let lt = l.topLevelTypes[k] else { continue }   // key removal handled above
        if bt != "null", lt != "null", bt != lt {
            d.breaking.append(Change(category: "Type changed (\(bt) -> \(lt))", detail: k))
        } else if bt != "null", lt == "null" {
            // A field going null is ambiguous from one snapshot: Anthropic may have
            // emptied/retired it (the Design bucket case this tool exists for), or
            // this account simply did not use it this period. Surface it as a
            // non-triggering note rather than an alert, to avoid usage-driven noise.
            d.notes.append(Change(category: "Field is null this run (was \(bt) in baseline)", detail: k))
        }
    }

    for (obj, bKeys) in b.objectFieldKeys {
        guard let lKeys = l.objectFieldKeys[obj] else { continue }  // presence covered by top-level diff / null note
        let fd = setDiff(bKeys, lKeys)
        fd.removed.forEach { d.breaking.append(Change(category: "Field removed", detail: "\(obj).\($0)")) }
        fd.added.forEach { d.additive.append(Change(category: "New field", detail: "\(obj).\($0)")) }
    }

    if b.limitsPresent && !l.limitsPresent { d.breaking.append(Change(category: "`limits` array is gone", detail: nil)) }
    if !b.limitsPresent && l.limitsPresent { d.additive.append(Change(category: "`limits` array appeared", detail: nil)) }

    let ek = setDiff(b.limitsEntryKeys, l.limitsEntryKeys)
    ek.removed.forEach { d.breaking.append(Change(category: "limits[] field removed", detail: $0)) }
    ek.added.forEach { d.additive.append(Change(category: "New limits[] field", detail: $0)) }

    let ki = setDiff(b.limitsKinds, l.limitsKinds)
    ki.removed.forEach { d.breaking.append(Change(category: "limits[].kind removed", detail: $0)) }
    ki.added.forEach { d.additive.append(Change(category: "New limits[].kind", detail: $0)) }

    let gr = setDiff(b.limitsGroups, l.limitsGroups)
    gr.removed.forEach { d.breaking.append(Change(category: "limits[].group removed", detail: $0)) }
    gr.added.forEach { d.additive.append(Change(category: "New limits[].group", detail: $0)) }

    // Model display names track which models were used this period, so they are
    // noisy by nature: reported for context, never a trigger on their own.
    let md = setDiff(b.limitsModelNames, l.limitsModelNames)
    md.added.forEach { d.notes.append(Change(category: "Model seen (not in baseline)", detail: $0)) }
    md.removed.forEach { d.notes.append(Change(category: "Model absent this run", detail: $0)) }

    return d
}

// MARK: - Encoding

let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
}()

func signatureJSON(_ sig: Signature) -> String {
    (try? encoder.encode(sig)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
}

/// Full report WITH names and the raw signature. Local only: printed by --dry-run
/// and written to the launchd log. Never posted to GitHub (see `publicReport`).
func report(_ d: Diff, live: Signature) -> String {
    func section(_ title: String, _ items: [Change]) -> String {
        items.isEmpty ? "### \(title)\n_None_\n" : "### \(title)\n" + items.map { "- \($0.full)" }.joined(separator: "\n") + "\n"
    }
    let now = ISO8601DateFormatter().string(from: Date())
    return """
    The live `/api/oauth/usage` response no longer matches the committed contract baseline (`Tools/contract-check/contract-baseline.json`). TokenEater's tolerant decoding would absorb this silently, so it is flagged here.

    \(section("Breaking changes", d.breaking))
    \(section("Additive changes", d.additive))
    \(section("Notes", d.notes))
    <details><summary>Current shape signature (no usage values)</summary>

    ```json
    \(signatureJSON(live))
    ```
    </details>

    ---
    To resolve: adapt `Shared/Models/UsageModels.swift`, run `Tools/contract-check/run.sh --update-baseline`, then close this issue.

    _Detected by `Tools/contract-check` at \(now)._
    """
}

/// Redacted body for the PUBLIC GitHub issue. Carries only category counts, never
/// the field/kind/model names or the raw signature (they can be unreleased
/// Anthropic codenames). The full diff lives in the maintainer's local log.
func publicReport(_ d: Diff) -> String {
    func summary(_ items: [Change]) -> String {
        if items.isEmpty { return "_None_" }
        var counts: [String: Int] = [:]
        for c in items { counts[c.category, default: 0] += 1 }
        return counts.sorted { $0.key < $1.key }.map { "- \($0.value)x \($0.key)" }.joined(separator: "\n")
    }
    let now = ISO8601DateFormatter().string(from: Date())
    return """
    The live `/api/oauth/usage` response no longer matches the committed contract baseline. TokenEater decodes that response tolerantly, so this would otherwise pass unnoticed.

    ### Breaking changes
    \(summary(d.breaking))

    ### Additive changes
    \(summary(d.additive))

    The exact field, kind and model names and the full shape diff are kept out of this public issue on purpose (they can include unreleased Anthropic API codenames). They are in the maintainer's local log: `~/Library/Logs/tokeneater-contract-check.log`.

    ### To resolve
    Adapt `Shared/Models/UsageModels.swift`, run `Tools/contract-check/run.sh --update-baseline`, then close this issue.

    _Detected by `Tools/contract-check` at \(now)._
    """
}

// MARK: - GitHub issue

func ghAvailable() -> Bool { run("/usr/bin/env", ["gh", "--version"], timeout: 10)?.0 == 0 }

func ensureLabel() {
    _ = run("/usr/bin/env", ["gh", "label", "create", issueLabel,
                             "--repo", repo,
                             "--color", "B60205",
                             "--description", "Anthropic usage API contract changed"], timeout: 15)
    // Ignore failure: the label most likely already exists.
}

enum IssueLookup { case found(String), none, failed }

func openIssue() -> IssueLookup {
    guard let (status, out, _) = run("/usr/bin/env",
        ["gh", "issue", "list", "--repo", repo, "--state", "open",
         "--label", issueLabel, "--json", "number", "--limit", "1"], timeout: 20),
        status == 0 else { return .failed }
    guard let data = out.data(using: .utf8),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return .failed
    }
    if let first = arr.first, let n = first["number"] as? Int { return .found(String(n)) }
    return .none
}

/// Posts the drift to GitHub. Returns true ONLY when an issue was actually created
/// or commented, so the caller records dedup state only on real success. A failed
/// or skipped post (gh missing, not authed, network, list error) returns false and
/// is retried next run instead of being silently swallowed forever.
func createOrComment(body: String) -> Bool {
    guard ghAvailable() else {
        log("gh not available or not authenticated; will retry next run.")
        return false
    }
    switch openIssue() {
    case .failed:
        log("Could not list existing issues (gh error); will retry next run.")
        return false
    case .found(let number):
        let commentBody = "New contract drift observed on top of the open report.\n\n" + body
        guard let (status, _, _) = run("/usr/bin/env",
            ["gh", "issue", "comment", number, "--repo", repo, "--body", commentBody], timeout: 30),
            status == 0 else {
            log("Failed to comment on issue #\(number); will retry next run.")
            return false
        }
        log("Commented on existing issue #\(number).")
        return true
    case .none:
        ensureLabel()
        guard let (status, out, _) = run("/usr/bin/env",
            ["gh", "issue", "create", "--repo", repo,
             "--title", issueTitle, "--label", issueLabel, "--body", body], timeout: 30),
            status == 0 else {
            log("Failed to create issue; will retry next run.")
            return false
        }
        log("Created issue: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        return true
    }
}

// MARK: - State (dedup across daily runs)

func lastDedupKey() -> String? {
    (try? String(contentsOf: stateURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func writeDedupKey(_ key: String?) {
    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    if let key, !key.isEmpty {
        try? key.write(to: stateURL, atomically: true, encoding: .utf8)
    } else {
        try? FileManager.default.removeItem(at: stateURL)
    }
}

// MARK: - Main

guard let token = readToken() else {
    log("Skipped: no OAuth token found (credentials file and Keychain both empty).")
    exit(0)
}

let fetched = fetchUsage(token: token)
guard case .ok(let data) = fetched else {
    if case .skip(let reason) = fetched { log("Skipped: \(reason).") }
    exit(0)
}

guard let live = buildSignature(from: data) else {
    log("Skipped: response was not a JSON object.")
    exit(0)
}

if printOnly {
    print(signatureJSON(live))
    exit(0)
}

if updateBaseline {
    do {
        try encoder.encode(live).write(to: baselineURL)
        log("Baseline updated: \(baselineURL.path)")
    } catch {
        log("Failed to write baseline: \(error.localizedDescription)")
        exit(1)
    }
    exit(0)
}

guard let baselineData = try? Data(contentsOf: baselineURL),
      let baseline = try? JSONDecoder().decode(Signature.self, from: baselineData) else {
    log("No baseline found. Run: Tools/contract-check/run.sh --update-baseline")
    exit(0)
}

let d = diff(baseline: baseline, live: live)
let body = report(d, live: live)

if dryRun {
    print(body)
    exit(0)
}

guard d.triggers else {
    // Contract matches: clear any stale dedup state so a future drift re-notifies.
    if lastDedupKey() != nil { writeDedupKey(nil) }
    log("No drift.")
    exit(0)
}

if d.dedupKey == lastDedupKey() {
    log("Drift already reported (unchanged since last run); not re-notifying.")
    exit(0)
}

// Full detail (with names) goes to the local log only; the public issue gets a
// redacted, codename-free summary. Dedup state is recorded ONLY if the post
// actually succeeded, so a failed/skipped post is retried on the next run.
log(body)
if createOrComment(body: publicReport(d)) {
    writeDedupKey(d.dedupKey)
} else {
    log("Issue not posted; dedup state left unchanged so the next run retries.")
}

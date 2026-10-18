import Foundation

/// The pure half of the usage-API contract canary: reduce a live response to a
/// value-free signature, compare it with the committed baseline, and grade each
/// difference against the paths TokenEater actually decodes.
///
/// No I/O lives here, so the test bundle compiles this file as-is and the
/// classification rules are covered by Swift Testing like the rest of the app.
/// Fetching, credentials and GitHub live in `main.swift`.
enum ContractCheck {

    // MARK: - States

    /// What a JSON path held. `absent` means the key was missing from an object
    /// that was itself present, which is how a rename shows up.
    enum State: String, Codable, CaseIterable, Comparable {
        case object, array, string, number, bool, null, absent

        static func < (lhs: State, rhs: State) -> Bool {
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
        }

        /// A state that carries data, as opposed to "nothing there".
        var isPresent: Bool { self != .null && self != .absent }
    }

    static func state(of value: Any) -> State {
        switch value {
        case is NSNull: return .null
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool : .number
        case is String: return .string
        case is [Any]: return .array
        case is [String: Any]: return .object
        default: return .null
        }
    }

    // MARK: - Read set

    /// `Tools/contract-check/read-set.json`: what each provider's decoder reads.
    struct ReadSet: Codable {
        let schema: Int
        let providers: [String: Provider]
    }

    struct Provider: Codable {
        let endpoint: String
        let decodedBy: [String]
        /// Paths whose values are recorded, so a new kind, model, window or plan
        /// is noticed. Only classification fields, never amounts or identities.
        let valueFields: [String]
        /// Objects keyed by data (model slugs), collapsed to `*` so a new model
        /// is not a new path.
        let dynamicKeys: [String]
        let ignoredCodingKeys: [String: String]?
        let paths: [String: ReadPath]
    }

    struct ReadPath: Codable {
        /// States the decoder turns into something useful. Anything else is a
        /// silent decode failure in the app.
        let types: [State]
        let use: String
        /// false when the path is decoded but feeds nothing visible.
        let displayed: Bool?

        var isDisplayed: Bool { displayed ?? true }
    }

    // MARK: - Signature

    /// The committed baseline format. Each path keeps every state ever
    /// acknowledged, so a field that is sometimes null and sometimes filled
    /// stops being news once both have been merged.
    struct Signature: Codable, Equatable {
        var schema = 2
        var endpoint: String
        var paths: [String: [State]] = [:]
        var values: [String: [String]] = [:]

        init(endpoint: String, paths: [String: [State]] = [:], values: [String: [String]] = [:]) {
            self.endpoint = endpoint
            self.paths = paths
            self.values = values
        }

        mutating func record(_ state: State, at path: String) {
            var states = Set(paths[path] ?? [])
            states.insert(state)
            paths[path] = states.sorted()
        }

        mutating func record(value: String, at path: String) {
            var known = Set(values[path] ?? [])
            guard !known.contains(value), known.count < ContractCheck.maxValuesPerField else { return }
            known.insert(value)
            values[path] = known.sorted()
        }
    }

    static let maxDepth = 8
    static let maxValuesPerField = 50

    /// Builds the signature of one response. Two passes: the first learns
    /// which keys exist, the second also records `absent` for every known key
    /// (from the baseline, the read set, or a sibling array entry) that an
    /// object is missing.
    static func signature(of response: Any, provider: Provider, baseline: Signature?) -> Signature {
        var known = Set(provider.paths.keys)
        if let baseline { known.formUnion(baseline.paths.keys) }

        var firstPass = Signature(endpoint: provider.endpoint)
        walk(response, path: "", depth: 0, provider: provider, children: children(of: known), into: &firstPass)
        known.formUnion(firstPass.paths.keys)

        var signature = Signature(endpoint: provider.endpoint)
        walk(response, path: "", depth: 0, provider: provider, children: children(of: known), into: &signature)
        return signature
    }

    private static func walk(
        _ value: Any,
        path: String,
        depth: Int,
        provider: Provider,
        children: [String: Set<String>],
        into signature: inout Signature
    ) {
        if !path.isEmpty {
            signature.record(state(of: value), at: path)
            if provider.valueFields.contains(path), let scalar = scalarDescription(value) {
                signature.record(value: scalar, at: path)
            }
        }
        guard depth < maxDepth else { return }

        if let object = value as? [String: Any] {
            let dynamic = provider.dynamicKeys.contains(path)
            for (key, child) in object {
                walk(child, path: join(path, dynamic ? "*" : key), depth: depth + 1,
                     provider: provider, children: children, into: &signature)
            }
            guard !dynamic else { return }
            for missing in (children[path] ?? []).subtracting(object.keys) {
                signature.record(.absent, at: join(path, missing))
            }
        } else if let array = value as? [Any] {
            for element in array {
                walk(element, path: path + "[]", depth: depth + 1,
                     provider: provider, children: children, into: &signature)
            }
        }
    }

    /// Strings and numbers only. Objects, arrays and booleans are not values
    /// worth tracking, and nothing here ever records an amount or an id: the
    /// read set only lists classification fields.
    private static func scalarDescription(_ value: Any) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.stringValue
        }
        return nil
    }

    static func join(_ parent: String, _ key: String) -> String {
        parent.isEmpty ? key : parent + "." + key
    }

    /// The object path a key path hangs off, and the key. nil for array element
    /// paths (`limits[]`), which are not keys of anything.
    static func split(_ path: String) -> (parent: String, key: String)? {
        guard !path.hasSuffix("[]") else { return nil }
        guard let dot = path.lastIndex(of: ".") else { return ("", path) }
        return (String(path[..<dot]), String(path[path.index(after: dot)...]))
    }

    private static func children(of paths: Set<String>) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for path in paths {
            guard let (parent, key) = split(path), key != "*" else { continue }
            result[parent, default: []].insert(key)
        }
        return result
    }

    /// Union of two signatures. The new baseline after a drift is the old one
    /// merged with what was observed, never a replacement, so a state seen
    /// once stays acknowledged.
    static func merge(_ lhs: Signature, _ rhs: Signature) -> Signature {
        var merged = lhs
        for (path, states) in rhs.paths {
            for state in states { merged.record(state, at: path) }
        }
        for (path, values) in rhs.values {
            for value in values { merged.record(value: value, at: path) }
        }
        return merged
    }

    // MARK: - Classification

    enum Severity: Int, Comparable, CaseIterable {
        /// A null-only key, or an unread key gone quiet. Never opens a PR alone.
        case dormant
        /// Something new TokenEater could use or should look at.
        case active
        /// A path TokenEater reads is missing or changed type.
        case breaking

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .dormant: return "dormant"
            case .active: return "active"
            case .breaking: return "breaking"
            }
        }
    }

    struct Change: Equatable {
        let path: String
        let severity: Severity
        let summary: String
    }

    /// Grades every state or value in `live` that `baseline` has not
    /// acknowledged yet. A nil baseline is the first capture for a provider.
    static func diff(baseline: Signature?, live: Signature, provider: Provider) -> [Change] {
        guard let baseline else {
            return [Change(path: "", severity: .active,
                           summary: "No baseline is committed yet: this records the first one.")]
        }

        var changes: [Change] = []
        var newPaths: Set<String> = []

        for path in live.paths.keys.sorted() {
            let liveStates = Set(live.paths[path] ?? [])
            let known = Set(baseline.paths[path] ?? [])
            let added = liveStates.subtracting(known)
            guard !added.isEmpty else { continue }
            if known.isEmpty { newPaths.insert(path) }
            changes.append(classify(path: path, added: added, known: known, provider: provider))
        }

        for path in live.values.keys.sorted() {
            let added = Set(live.values[path] ?? []).subtracting(baseline.values[path] ?? [])
            guard !added.isEmpty else { continue }
            changes.append(Change(path: path, severity: .active,
                                  summary: "new value \(list(added.sorted())) for `\(path)`"))
        }

        return fold(changes, under: newPaths)
    }

    private static func classify(path: String, added: Set<State>, known: Set<State>, provider: Provider) -> Change {
        let addedText = list(added.sorted().map(\.rawValue))
        let wasText = known.isEmpty ? "" : " (was \(list(known.sorted().map(\.rawValue))))"
        let verb = known.isEmpty ? "first seen as" : "is now"

        if let read = provider.paths[path] {
            let unexpected = added.subtracting(read.types)
            if !unexpected.isEmpty {
                let severity: Severity = read.isDisplayed ? .breaking : .active
                let what = unexpected == [.absent]
                    ? "`\(path)` is missing"
                    : "`\(path)` \(verb) \(list(unexpected.sorted().map(\.rawValue)))"
                let expects = list(read.types.sorted().map(\.rawValue))
                return Change(path: path, severity: severity,
                              summary: "\(what)\(wasText), TokenEater decodes \(expects). Used for: \(read.use)")
            }
            if added.contains(where: \.isPresent) {
                return Change(path: path, severity: .active,
                              summary: "`\(path)` \(verb) \(addedText)\(wasText). Used for: \(read.use)")
            }
            return Change(path: path, severity: .dormant, summary: "`\(path)` \(verb) \(addedText)\(wasText)")
        }

        if known.isEmpty {
            if let parent = parentObject(of: path), let read = provider.paths[parent], read.types.contains(.object) {
                return Change(path: path, severity: .active,
                              summary: "new field `\(path)` (\(addedText)) on `\(parent)`, which TokenEater reads")
            }
            if added.contains(where: \.isPresent) {
                return Change(path: path, severity: .active, summary: "new `\(path)` (\(addedText))")
            }
            return Change(path: path, severity: .dormant, summary: "new `\(path)` (\(addedText))")
        }

        if added.contains(where: \.isPresent) {
            return Change(path: path, severity: .active, summary: "`\(path)` is now \(addedText)\(wasText)")
        }
        return Change(path: path, severity: .dormant, summary: "`\(path)` is now \(addedText)\(wasText)")
    }

    /// The object a key belongs to, seen through array entries: the parent of
    /// `limits[].severity` is the entry object `limits[]`.
    private static func parentObject(of path: String) -> String? {
        guard let (parent, _) = split(path), !parent.isEmpty else { return nil }
        return parent
    }

    /// A brand-new object reports once, with its field count, instead of once
    /// per field.
    private static func fold(_ changes: [Change], under newPaths: Set<String>) -> [Change] {
        func newAncestor(of path: String) -> String? {
            newPaths.filter { $0 != path && (path.hasPrefix($0 + ".") || path.hasPrefix($0 + "[]")) }
                .min { $0.count < $1.count }
        }
        var folded: [String: Int] = [:]
        var kept: [Change] = []
        for change in changes {
            if let ancestor = newAncestor(of: change.path), !change.path.isEmpty {
                folded[ancestor, default: 0] += 1
            } else {
                kept.append(change)
            }
        }
        return kept.map { change in
            guard let count = folded[change.path] else { return change }
            let fields = count == 1 ? "1 nested path" : "\(count) nested paths"
            return Change(path: change.path, severity: change.severity, summary: "\(change.summary), with \(fields)")
        }
    }

    private static func list(_ items: [String]) -> String {
        items.map { "`\($0)`" }.joined(separator: ", ")
    }

    // MARK: - Report

    struct ProviderReport {
        let name: String
        let endpoint: String
        let changes: [Change]

        var highest: Severity? { changes.map(\.severity).max() }
        func count(_ severity: Severity) -> Int { changes.filter { $0.severity == severity }.count }
    }

    /// The PR body. The first line is machine-read by the drift workflow for
    /// the PR title.
    static func report(_ providers: [ProviderReport], capturedAt: String, tool: String) -> String {
        let highest = providers.compactMap(\.highest).max() ?? .dormant
        var lines = [
            "<!-- contract-drift severity=\(highest.label) -->",
            "The live usage responses no longer match the committed baselines in `Tools/contract-check/baselines/`. TokenEater decodes them tolerantly, so this would otherwise go unnoticed until a card silently empties.",
            "",
            "| Provider | Breaking | Active | Dormant |",
            "|----------|----------|--------|---------|",
        ]
        for provider in providers {
            lines.append("| \(provider.name) | \(provider.count(.breaking)) | \(provider.count(.active)) | \(provider.count(.dormant)) |")
        }

        for provider in providers where !provider.changes.isEmpty {
            lines += ["", "### \(provider.name) (`\(provider.endpoint)`)"]
            for severity in Severity.allCases.reversed() {
                let items = provider.changes.filter { $0.severity == severity }
                guard !items.isEmpty else { continue }
                lines += ["", "**\(heading(for: severity))**", ""]
                lines += items.map { "- \($0.summary)" }
            }
        }

        lines += [
            "",
            "### What to do",
            "",
            "- Breaking: fix the decoder (`Shared/Models/UsageModels.swift` or `Shared/Models/CodexUsageModels.swift`) in a separate PR, then merge this one.",
            "- Active: decide whether TokenEater should use it. Either way, merging this PR acknowledges it.",
            "- Dormant entries ride along and need nothing.",
            "",
            "Merging moves the committed baseline forward, so these changes stop being reported. Closing without merging only dismisses the PR: the same drift opens a new one at the next weekly run.",
            "",
            "_Captured by `Tools/contract-check` at \(capturedAt) (build \(tool))._",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func heading(for severity: Severity) -> String {
        switch severity {
        case .breaking: return "Breaking: a path TokenEater reads is missing or changed type"
        case .active: return "Active: new data, or data that came back"
        case .dormant: return "Dormant: batched, no action needed"
        }
    }

    // MARK: - Baseline file

    /// One path per line with sorted keys, so a baseline diff in a PR reads
    /// like a changelog.
    static func encode(_ signature: Signature) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        func quoted(_ string: String) -> String {
            let data = try? encoder.encode(string)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        }
        func block(_ entries: [String: [String]]) -> String {
            guard !entries.isEmpty else { return "{}" }
            let rows = entries.keys.sorted().map { key in
                "    \(quoted(key)): [\(entries[key]!.map(quoted).joined(separator: ", "))]"
            }
            return "{\n" + rows.joined(separator: ",\n") + "\n  }"
        }
        let paths = signature.paths.mapValues { $0.sorted().map(\.rawValue) }
        return """
        {
          "schema": \(signature.schema),
          "endpoint": \(quoted(signature.endpoint)),
          "paths": \(block(paths)),
          "values": \(block(signature.values))
        }

        """
    }

    static func decodeSignature(_ data: Data) throws -> Signature {
        try JSONDecoder().decode(Signature.self, from: data)
    }

    static func decodeReadSet(_ data: Data) throws -> ReadSet {
        try JSONDecoder().decode(ReadSet.self, from: data)
    }
}

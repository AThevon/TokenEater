import Testing
import Foundation

/// The classification rules of the usage-API contract canary
/// (`Tools/contract-check`). The tool itself runs on the maintainer's Mac;
/// what is tested here is the part that decides whether a payload change
/// opens a PR, and how loudly.
@Suite("Contract check")
struct ContractCheckTests {

    // MARK: - Fixtures

    private static let toolDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tools/contract-check")

    private static func readSet() throws -> ContractCheck.ReadSet {
        try ContractCheck.decodeReadSet(Data(contentsOf: toolDirectory.appendingPathComponent("read-set.json")))
    }

    private static func provider(_ key: String) throws -> ContractCheck.Provider {
        try #require(try readSet().providers[key])
    }

    /// The live Claude shape, values made up.
    private static let claudeJSON = """
    {
      "five_hour": { "utilization": 12.0, "resets_at": "2026-10-13T20:00:00Z", "locked_reason": null },
      "seven_day": { "utilization": 40.0, "resets_at": "2026-10-17T08:00:00Z", "locked_reason": null },
      "seven_day_sonnet": null,
      "seven_day_opus": null,
      "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null,
                       "utilization": null, "currency": null, "disabled_reason": null },
      "amber_ladder": null,
      "limits": [
        { "kind": "session", "group": "session", "percent": 12, "resets_at": "2026-10-13T20:00:00Z",
          "scope": null, "severity": "normal" },
        { "kind": "weekly_scoped", "group": "weekly", "percent": 23, "resets_at": "2026-10-17T08:00:00Z",
          "scope": { "model": { "id": null, "display_name": "Fable" } }, "severity": "normal" }
      ]
    }
    """

    private static func json(_ text: String) -> Any {
        try! JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    private static func signature(
        _ text: String,
        _ provider: ContractCheck.Provider,
        baseline: ContractCheck.Signature? = nil
    ) -> ContractCheck.Signature {
        ContractCheck.signature(of: json(text), provider: provider, baseline: baseline)
    }

    /// The Claude fixture with one substring swapped, signed against the
    /// unmodified fixture as baseline.
    private static func claudeChanges(replacing old: String, with new: String) throws -> [ContractCheck.Change] {
        let provider = try provider("claude-usage")
        let baseline = signature(claudeJSON, provider)
        let changed = claudeJSON.replacingOccurrences(of: old, with: new)
        #expect(changed != claudeJSON, "the replacement did not apply")
        let live = signature(changed, provider, baseline: baseline)
        return ContractCheck.diff(baseline: baseline, live: live, provider: provider)
    }

    private static func severity(of path: String, in changes: [ContractCheck.Change]) -> ContractCheck.Severity? {
        changes.first { $0.path == path }?.severity
    }

    // MARK: - Read set and committed files

    @Test("the read set decodes and every value field is a declared path")
    func readSetIsConsistent() throws {
        let readSet = try Self.readSet()
        #expect(Set(readSet.providers.keys) == ["claude-usage", "codex-usage"])
        for provider in readSet.providers.values {
            for (path, entry) in provider.paths {
                #expect(!entry.types.isEmpty, "\(path) accepts no type")
            }
            for field in provider.valueFields {
                #expect(provider.paths[field] != nil, "\(field) records values but is not a read path")
            }
        }
    }

    @Test("the committed Claude baseline is a v2 signature that fits the read set")
    func committedBaselineFitsReadSet() throws {
        let url = Self.toolDirectory.appendingPathComponent("baselines/claude-usage.json")
        let baseline = try ContractCheck.decodeSignature(Data(contentsOf: url))
        let provider = try Self.provider("claude-usage")
        #expect(baseline.schema == 2)
        #expect(baseline.endpoint == provider.endpoint)
        for (path, states) in baseline.paths {
            guard let read = provider.paths[path] else { continue }
            #expect(Set(states).isSubset(of: read.types), "\(path) holds \(states), the app decodes \(read.types)")
        }
        // Encoding is stable, so a merge with nothing new rewrites nothing.
        #expect(ContractCheck.encode(baseline) == (try String(contentsOf: url, encoding: .utf8)))
    }

    @Test("the recorded Codex captures fit the Codex read set")
    func codexCapturesFitReadSet() throws {
        let provider = try Self.provider("codex-usage")
        for capture in [CodexFixtures.proliteJSON, CodexFixtures.plusJSON] {
            let signature = Self.signature(capture, provider)
            for (path, states) in signature.paths {
                guard let read = provider.paths[path] else { continue }
                #expect(Set(states).isSubset(of: read.types), "\(path) holds \(states), the app decodes \(read.types)")
            }
        }
    }

    @Test("values are recorded only for classification fields, never identities")
    func noIdentityValues() throws {
        let provider = try Self.provider("codex-usage")
        let signature = Self.signature(CodexFixtures.proliteJSON, provider)

        #expect(Set(signature.values.keys).isSubset(of: Set(provider.valueFields)))
        let recorded = signature.values.values.flatMap { $0 }
        #expect(!recorded.contains("redacted@example.com"))
        #expect(!recorded.contains("00000000-0000-0000-0000-000000000000"))
        #expect(signature.values["plan_type"] == ["prolite"])
        #expect(signature.values["rate_limit.primary_window.limit_window_seconds"] == ["604800"])
        // The key is part of the shape; its value is not.
        #expect(signature.paths["email"] == [.string])
    }

    // MARK: - Breaking

    @Test("a read number turning into a string is breaking")
    func typeChangeOnReadPathIsBreaking() throws {
        let changes = try Self.claudeChanges(replacing: #""utilization": 12.0"#, with: #""utilization": "12""#)
        #expect(Self.severity(of: "five_hour.utilization", in: changes) == .breaking)
    }

    @Test("a renamed model display name is breaking, not a quiet note")
    func renamedDisplayNameIsBreaking() throws {
        let changes = try Self.claudeChanges(replacing: #""display_name": "Fable""#, with: #""name": "Fable""#)
        #expect(Self.severity(of: "limits[].scope.model.display_name", in: changes) == .breaking)
        #expect(Self.severity(of: "limits[].scope.model.name", in: changes) == .active)
    }

    @Test("a read bucket going null is breaking when the app needs it")
    func requiredBucketGoingNullIsBreaking() throws {
        let changes = try Self.claudeChanges(
            replacing: #""seven_day": { "utilization": 40.0, "resets_at": "2026-10-17T08:00:00Z", "locked_reason": null }"#,
            with: #""seven_day": null"#)
        #expect(Self.severity(of: "seven_day", in: changes) == .breaking)
    }

    @Test("a violation on a decoded but undisplayed path is only active")
    func undisplayedViolationIsActive() throws {
        let provider = try Self.provider("codex-usage")
        let baseline = Self.signature(CodexFixtures.plusJSON, provider)
        let changed = CodexFixtures.plusJSON.replacingOccurrences(
            of: #""individual_limit": null"#,
            with: #""individual_limit": { "limit": "25000" }"#)
        let live = Self.signature(changed, provider, baseline: baseline)
        let changes = ContractCheck.diff(baseline: baseline, live: live, provider: provider)
        #expect(Self.severity(of: "spend_control.individual_limit.limit", in: changes) == .active)
    }

    // MARK: - Active

    @Test("a new field on an object the app reads is active even while null")
    func newFieldOnReadObjectIsActive() throws {
        let changes = try Self.claudeChanges(replacing: #""locked_reason": null }"#, with: #""locked_reason": null, "used_dollars": null }"#)
        #expect(Self.severity(of: "five_hour.used_dollars", in: changes) == .active)
    }

    @Test("a dormant per-model bucket filling up is active")
    func nullToObjectIsActive() throws {
        let changes = try Self.claudeChanges(
            replacing: #""seven_day_sonnet": null"#,
            with: #""seven_day_sonnet": { "utilization": 5, "resets_at": null }"#)
        #expect(Self.severity(of: "seven_day_sonnet", in: changes) == .active)
    }

    @Test("a new limit kind is active")
    func newKindIsActive() throws {
        let changes = try Self.claudeChanges(replacing: #""kind": "session""#, with: #""kind": "daily""#)
        #expect(Self.severity(of: "limits[].kind", in: changes) == .active)
    }

    @Test("a new filled object reports once, with its nested paths folded in")
    func newObjectIsFolded() throws {
        let changes = try Self.claudeChanges(
            replacing: #""amber_ladder": null"#,
            with: #""amber_ladder": null, "spend": { "enabled": true, "used": { "amount_minor": 0 } }"#)
        #expect(changes.map(\.path) == ["spend"])
        #expect(changes.first?.severity == .active)
        #expect(changes.first?.summary.contains("3 nested paths") == true)
    }

    // MARK: - Dormant and quiet

    @Test("a new null-only key is dormant")
    func newNullKeyIsDormant() throws {
        let changes = try Self.claudeChanges(replacing: #""amber_ladder": null"#, with: #""amber_ladder": null, "copper_kite": null"#)
        #expect(changes.count == 1)
        #expect(Self.severity(of: "copper_kite", in: changes) == .dormant)
    }

    @Test("an unread key going quiet is dormant")
    func unreadKeyRemovalIsDormant() throws {
        let changes = try Self.claudeChanges(replacing: #""amber_ladder": null,"#, with: "")
        #expect(Self.severity(of: "amber_ladder", in: changes) == .dormant)
    }

    @Test("a state already acknowledged never comes back")
    func acknowledgedStatesStayQuiet() throws {
        let provider = try Self.provider("claude-usage")
        let filled = Self.claudeJSON.replacingOccurrences(
            of: #""seven_day_sonnet": null"#,
            with: #""seven_day_sonnet": { "utilization": 5, "resets_at": null }"#)
        let merged = ContractCheck.merge(Self.signature(Self.claudeJSON, provider), Self.signature(filled, provider))

        // Null one week, filled the next: both are in the baseline now.
        for week in [Self.claudeJSON, filled] {
            let live = Self.signature(week, provider, baseline: merged)
            #expect(ContractCheck.diff(baseline: merged, live: live, provider: provider).isEmpty)
        }
    }

    @Test("a new model under a data-keyed object is not a new path")
    func dynamicKeysCollapse() throws {
        let provider = try Self.provider("codex-usage")
        let baseline = Self.signature(CodexFixtures.proliteJSON, provider)
        let changed = CodexFixtures.proliteJSON.replacingOccurrences(of: "gpt-6-astra", with: "gpt-7-nova")
        let live = Self.signature(changed, provider, baseline: baseline)
        #expect(ContractCheck.diff(baseline: baseline, live: live, provider: provider).isEmpty)
        #expect(baseline.paths["model_usage.*.available"] == [.bool])
    }

    @Test("no committed baseline yields a single first-capture change")
    func missingBaselineBootstraps() throws {
        let provider = try Self.provider("codex-usage")
        let live = Self.signature(CodexFixtures.plusJSON, provider)
        let changes = ContractCheck.diff(baseline: nil, live: live, provider: provider)
        #expect(changes.count == 1)
        #expect(changes.first?.severity == .active)
    }

    // MARK: - Files

    @Test("the baseline format round-trips")
    func encodingRoundTrips() throws {
        let provider = try Self.provider("claude-usage")
        let signature = Self.signature(Self.claudeJSON, provider)
        let decoded = try ContractCheck.decodeSignature(Data(ContractCheck.encode(signature).utf8))
        #expect(decoded == signature)
        #expect(ContractCheck.encode(signature).contains(#""endpoint": "GET https://api.anthropic.com/api/oauth/usage""#))
    }

    @Test("the report leads with the highest severity for the PR title")
    func reportHeader() {
        let report = ContractCheck.report([
            .init(name: "Claude", endpoint: "GET x", changes: [
                .init(path: "a", severity: .dormant, summary: "new `a`"),
                .init(path: "b", severity: .breaking, summary: "`b` is missing"),
            ]),
        ], capturedAt: "2026-10-13T00:00:00Z", tool: "test")
        #expect(report.hasPrefix("<!-- contract-drift severity=breaking -->"))
        #expect(report.contains("| Claude | 1 | 0 | 1 |"))
    }
}

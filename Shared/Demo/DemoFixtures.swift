import Foundation

// MARK: - Demo fixtures
//
// The fake accounts the multi-account demo mode serves (see `DemoMode`). Pure
// data and pure functions of the date: nothing here reads a file, the
// Keychain or the network. Every value is deterministic for a given date, so
// the numbers drift slowly from one refresh to the next and two launches
// started at the same moment agree.

/// How a fake folder's login behaves.
enum DemoLogin: Equatable, Sendable {
    /// A login Anthropic accepts: profile and usage answer.
    case valid
    /// A login Anthropic refuses: every call is a 401, and its token
    /// expired just after the last numbers it shows were fetched
    /// (`DemoFixtures.expiredAt`).
    case expired
    /// No login in the folder at all.
    case none
}

/// The plan a fake login reports, through the same profile fields a real
/// `/profile` answer carries.
enum DemoPlan: Equatable, Sendable {
    case pro
    case max
    case team
}

/// One fake usage pool: where it sits, how far it swings, and where its
/// window resets relative to the shared grid.
struct DemoPool: Equatable, Sendable {
    let base: Double
    let swing: Double
    /// Shifts the pool's reset on the grid, so two accounts never reset at
    /// the same minute.
    let resetOffsetMinutes: Double
}

/// The paid Extra Credits pool, in minor units like the API.
struct DemoExtraCredits: Equatable, Sendable {
    let monthlyLimit: Double
    let usedCredits: Double
}

/// Model mix and rhythm of a fake account's transcripts, for History and
/// the dashboard insights.
struct DemoHistoryShape: Equatable, Sendable {
    /// Active tokens in a busy hour.
    let tokensPerHour: Int
    /// Share of each model, summing to 1.
    let models: [(ModelKind, Double)]
    let projects: [String]
    /// No activity after this long before the demo started (an account that
    /// went quiet: expired, paused).
    let quietFor: TimeInterval?

    static func == (lhs: DemoHistoryShape, rhs: DemoHistoryShape) -> Bool {
        lhs.tokensPerHour == rhs.tokensPerHour
            && lhs.models.map(\.0) == rhs.models.map(\.0)
            && lhs.models.map(\.1) == rhs.models.map(\.1)
            && lhs.projects == rhs.projects
            && lhs.quietFor == rhs.quietFor
    }
}

/// A fake Claude Code config folder and the login it holds.
struct DemoClaudeFixture: Equatable, Sendable, Identifiable {
    /// Stable key: the seeded account's id is `acct-demo-<key>`.
    let key: String
    /// The folder under home, `.claude-demo-<something>`. Never created.
    let folderName: String
    let name: String
    let colorHex: String
    /// Tracked when the demo starts. The others are only offered by the
    /// add-account sheet.
    let seeded: Bool
    let isPaused: Bool
    let login: DemoLogin
    /// The fixture whose identity this login carries: itself, or another
    /// fixture's for a second folder signed in to the same account.
    let identityKey: String
    let plan: DemoPlan
    let email: String
    let organizationName: String?
    let fiveHour: DemoPool
    let weekly: DemoPool
    /// The one model-scoped weekly limit live accounts still carry (a
    /// `limits[]` entry tagged "Fable"). Sonnet and Opus pools are not
    /// modelled: Anthropic stopped sending them, and the demo shows only
    /// what a live account can show.
    let fable: DemoPool?
    let extraCredits: DemoExtraCredits?
    /// Last numbers written for it when the demo starts, this long before:
    /// what a paused or expired account keeps showing.
    let lastNumbersAgo: TimeInterval?
    let history: DemoHistoryShape

    var id: String { key }

    var accountID: AccountID { AccountID(rawValue: "acct-demo-" + key) }

    func folderPath(home: String) -> String {
        ClaudeConfigDirResolver.normalize(home + "/" + folderName, home: home)
    }

    /// The Keychain service Claude Code would use for the folder, so the
    /// record and the scope look exactly like a real added account's.
    func service(home: String) -> String {
        ClaudeConfigDirResolver.service(forHashInput: folderPath(home: home))
    }

    /// The token the fake provider hands out, which `DemoAPIClient`
    /// recognises. Never sent anywhere: a demo token is answered in memory.
    var token: String { DemoFixtures.tokenPrefix + key }
}

enum DemoFixtures {
    static let tokenPrefix = "demo-token."
    static let codexToken = "demo-token.codex"

    // MARK: - The accounts

    static let work = DemoClaudeFixture(
        key: "work",
        folderName: ".claude-demo-work",
        name: "Work",
        colorHex: "#F472B6",
        seeded: true,
        isPaused: false,
        login: .valid,
        identityKey: "work",
        plan: .team,
        email: "ada@acme-robotics.dev",
        organizationName: "Acme Robotics",
        fiveHour: DemoPool(base: 88, swing: 6, resetOffsetMinutes: 0),
        weekly: DemoPool(base: 30, swing: 2, resetOffsetMinutes: 0),
        fable: DemoPool(base: 63, swing: 4, resetOffsetMinutes: 0),
        extraCredits: DemoExtraCredits(monthlyLimit: 20_000, usedCredits: 4_750),
        lastNumbersAgo: nil,
        history: DemoHistoryShape(
            tokensPerHour: 420_000,
            models: [(.opus55, 0.5), (.sonnet55, 0.35), (.fable, 0.15)],
            projects: ["/demo/acme-api", "/demo/acme-web", "/demo/robot-firmware"],
            quietFor: nil
        )
    )

    /// Twelve characters, the longest name the field takes, so the menu bar
    /// shows its ellipsis.
    static let side = DemoClaudeFixture(
        key: "side",
        folderName: ".claude-demo-side",
        name: "Side project",
        colorHex: "#22D3EE",
        seeded: true,
        isPaused: false,
        login: .valid,
        identityKey: "side",
        plan: .max,
        email: "sam@hey-demo.dev",
        organizationName: nil,
        fiveHour: DemoPool(base: 9, swing: 4, resetOffsetMinutes: 95),
        weekly: DemoPool(base: 14, swing: 2, resetOffsetMinutes: 1_800),
        fable: nil,
        extraCredits: nil,
        lastNumbersAgo: nil,
        history: DemoHistoryShape(
            tokensPerHour: 90_000,
            models: [(.sonnet55, 0.7), (.haiku, 0.3)],
            projects: ["/demo/side-project", "/demo/blog"],
            quietFor: nil
        )
    )

    static let expired = DemoClaudeFixture(
        key: "old",
        folderName: ".claude-demo-old",
        name: "Old login",
        colorHex: "#C084FC",
        seeded: true,
        isPaused: false,
        login: .expired,
        identityKey: "old",
        plan: .pro,
        email: "lee@oldmail-demo.dev",
        organizationName: nil,
        fiveHour: DemoPool(base: 47, swing: 0, resetOffsetMinutes: 40),
        weekly: DemoPool(base: 71, swing: 0, resetOffsetMinutes: 600),
        fable: nil,
        extraCredits: nil,
        lastNumbersAgo: DemoFixtures.expiredLastNumbersAgo,
        history: DemoHistoryShape(
            tokensPerHour: 150_000,
            models: [(.opus5, 0.6), (.sonnet5, 0.4)],
            projects: ["/demo/legacy-app"],
            quietFor: 2 * 86_400
        )
    )

    static let paused = DemoClaudeFixture(
        key: "paused",
        folderName: ".claude-demo-paused",
        name: "Paused",
        colorHex: "#6366F1",
        seeded: true,
        isPaused: true,
        login: .valid,
        identityKey: "paused",
        plan: .pro,
        email: "kim@freelance-demo.dev",
        organizationName: nil,
        fiveHour: DemoPool(base: 22, swing: 3, resetOffsetMinutes: 150),
        weekly: DemoPool(base: 55, swing: 2, resetOffsetMinutes: 3_000),
        fable: nil,
        extraCredits: nil,
        lastNumbersAgo: 3 * 3600,
        history: DemoHistoryShape(
            tokensPerHour: 120_000,
            models: [(.sonnet55, 1.0)],
            projects: ["/demo/client-site"],
            quietFor: 86_400
        )
    )

    /// Offered by the add sheet, with a login: Connect succeeds.
    static let client = DemoClaudeFixture(
        key: "client",
        folderName: ".claude-demo-client",
        name: "Client",
        colorHex: "#8B7CF6",
        seeded: false,
        isPaused: false,
        login: .valid,
        identityKey: "client",
        plan: .pro,
        email: "max@globex-demo.dev",
        organizationName: nil,
        fiveHour: DemoPool(base: 35, swing: 5, resetOffsetMinutes: 210),
        weekly: DemoPool(base: 48, swing: 2, resetOffsetMinutes: 4_200),
        fable: nil,
        extraCredits: nil,
        lastNumbersAgo: nil,
        history: DemoHistoryShape(
            tokensPerHour: 200_000,
            models: [(.opus55, 0.4), (.sonnet55, 0.6)],
            projects: ["/demo/globex-portal"],
            quietFor: nil
        )
    )

    /// Offered by the add sheet, with no login: Connect is refused with the
    /// folder's login command.
    static let empty = DemoClaudeFixture(
        key: "empty",
        folderName: ".claude-demo-empty",
        name: "Empty",
        colorHex: "#94A3B8",
        seeded: false,
        isPaused: false,
        login: .none,
        identityKey: "empty",
        plan: .pro,
        email: "nobody@demo.dev",
        organizationName: nil,
        fiveHour: DemoPool(base: 0, swing: 0, resetOffsetMinutes: 0),
        weekly: DemoPool(base: 0, swing: 0, resetOffsetMinutes: 0),
        fable: nil,
        extraCredits: nil,
        lastNumbersAgo: nil,
        history: DemoHistoryShape(tokensPerHour: 0, models: [], projects: [], quietFor: nil)
    )

    /// Offered by the add sheet, signed in to the same login as Work:
    /// Connect is refused as a duplicate of Work.
    static let copy = DemoClaudeFixture(
        key: "copy",
        folderName: ".claude-demo-copy",
        name: "Copy",
        colorHex: "#E879F9",
        seeded: false,
        isPaused: false,
        login: .valid,
        identityKey: "work",
        plan: .team,
        email: work.email,
        organizationName: work.organizationName,
        fiveHour: work.fiveHour,
        weekly: work.weekly,
        fable: work.fable,
        extraCredits: work.extraCredits,
        lastNumbersAgo: nil,
        history: work.history
    )

    static let claude: [DemoClaudeFixture] = [work, side, expired, paused, client, empty, copy]

    static var seeded: [DemoClaudeFixture] { claude.filter(\.seeded) }

    static func fixture(key: String) -> DemoClaudeFixture? {
        claude.first { $0.key == key }
    }

    /// The fixture a folder stands for, nil for any folder that is not one
    /// of the demo's.
    static func fixture(forFolder path: String?, home: String) -> DemoClaudeFixture? {
        guard let path else { return nil }
        let normalized = ClaudeConfigDirResolver.normalize(path, home: home)
        return claude.first { $0.folderPath(home: home) == normalized }
    }

    static func fixture(forScope scope: CredentialScope, home: String) -> DemoClaudeFixture? {
        guard case .configDir(let path, _) = scope else { return nil }
        return fixture(forFolder: path, home: home)
    }

    static func fixture(forToken token: String) -> DemoClaudeFixture? {
        guard token.hasPrefix(tokenPrefix) else { return nil }
        return fixture(key: String(token.dropFirst(tokenPrefix.count)))
    }

    /// The record a seeded fixture is tracked under: the same shape an
    /// added account has, with the identity digest already pinned so the
    /// duplicate check works from the first second.
    static func record(for fixture: DemoClaudeFixture, home: String, now: Date) -> ClaudeAccountRecord {
        ClaudeAccountRecord(
            id: fixture.accountID,
            configDir: fixture.folderPath(home: home),
            service: fixture.service(home: home),
            name: fixture.name,
            colorHex: fixture.colorHex,
            isPaused: fixture.isPaused,
            notificationsEnabled: true,
            identityDigest: identityDigest(of: fixture),
            addedAt: now
        )
    }

    // MARK: - Identity

    static func identityDigest(of fixture: DemoClaudeFixture) -> String {
        let profile = profile(for: fixture)
        return ClaudeConfigDirResolver.identityDigest(
            accountUUID: profile.account.uuid,
            organizationUUID: profile.organization?.uuid
        )
    }

    static func profile(for fixture: DemoClaudeFixture) -> ProfileResponse {
        let owner = self.fixture(key: fixture.identityKey) ?? fixture
        let organization: OrganizationInfo?
        switch owner.plan {
        case .team:
            organization = OrganizationInfo(
                uuid: "00000000-de30-4000-9000-" + hex12(stableHash("org." + owner.key)),
                name: owner.organizationName ?? "Demo team",
                organizationType: "claude_team",
                billingType: "stripe_subscription",
                rateLimitTier: "default_claude_team"
            )
        case .pro, .max:
            organization = nil
        }
        return ProfileResponse(
            account: AccountInfo(
                uuid: "00000000-de30-4000-8000-" + hex12(stableHash(owner.key)),
                fullName: owner.name + " (demo)",
                displayName: owner.name,
                email: owner.email,
                hasClaudeMax: owner.plan == .max,
                hasClaudePro: owner.plan == .pro
            ),
            organization: organization
        )
    }

    // MARK: - Usage

    /// The usage answer at `now`: each pool swings slowly around its base
    /// (a period of about an hour), and resets on a fixed grid, so pacing,
    /// colours and countdowns move from one refresh to the next the way real
    /// numbers do.
    static func usage(for fixture: DemoClaudeFixture, at now: Date, startedAt: Date) -> UsageResponse {
        let minutes = now.timeIntervalSince(startedAt) / 60
        func bucket(_ pool: DemoPool?, window: TimeInterval, phase: Double) -> UsageBucket? {
            guard let pool else { return nil }
            let value = pool.base + pool.swing * sin(minutes / 9 + phase)
            return UsageBucket(
                utilization: min(100, max(0, (value * 10).rounded() / 10)),
                resetsAt: iso(nextReset(after: now, window: window, offsetMinutes: pool.resetOffsetMinutes))
            )
        }
        let week: TimeInterval = 7 * 86_400
        return UsageResponse(
            fiveHour: bucket(fixture.fiveHour, window: 5 * 3600, phase: 0),
            sevenDay: bucket(fixture.weekly, window: week, phase: 1),
            sevenDayFable: bucket(fixture.fable, window: week, phase: 4),
            extraUsage: fixture.extraCredits.map { credits in
                ExtraUsage(
                    isEnabled: true,
                    monthlyLimit: credits.monthlyLimit,
                    usedCredits: credits.usedCredits + (minutes * 3).rounded(),
                    utilization: nil,
                    currency: "USD",
                    disabledReason: nil
                )
            }
        )
    }

    /// The next reset of a window on a grid anchored at a fixed date, so it
    /// stays put between refreshes and moves on only when the window rolls.
    static func nextReset(after now: Date, window: TimeInterval, offsetMinutes: Double) -> Date {
        let anchor = gridAnchor.addingTimeInterval(offsetMinutes * 60)
        let elapsed = now.timeIntervalSince(anchor)
        let windows = (elapsed / window).rounded(.down) + 1
        return anchor.addingTimeInterval(windows * window)
    }

    /// Thursday 1 January 2026, 08:00 UTC.
    static let gridAnchor = Date(timeIntervalSince1970: 1_767_254_400)

    /// How old the expired fixture's numbers are when the demo starts.
    static let expiredLastNumbersAgo: TimeInterval = 2 * 86_400

    /// When an expired fixture's login stopped working: five minutes after
    /// its last numbers were fetched, as a real login stops answering just
    /// after its last good refresh, so "expired 2 days ago" and "last numbers
    /// 2 days ago" agree. Long past the hour of calm the app gives a routine
    /// expiry, so the escalated state shows at once.
    static func expiredAt(startedAt: Date) -> Date {
        startedAt.addingTimeInterval(-expiredLastNumbersAgo + 300)
    }

    /// The 5h readings that would have been recorded since the current
    /// window opened, one every twenty minutes, for the hero pacing graph.
    static func sessionSamples(for fixture: DemoClaudeFixture, now: Date, startedAt: Date) -> [PacingSample] {
        let reset = nextReset(after: now, window: 5 * 3600, offsetMinutes: fixture.fiveHour.resetOffsetMinutes)
        let windowStart = reset.addingTimeInterval(-5 * 3600)
        let current = usage(for: fixture, at: now, startedAt: startedAt).fiveHour?.utilization ?? 0
        var samples: [PacingSample] = []
        var date = windowStart.addingTimeInterval(10 * 60)
        while date < now.addingTimeInterval(-60) {
            let fraction = date.timeIntervalSince(windowStart) / now.timeIntervalSince(windowStart)
            samples.append(PacingSample(date: date, utilization: (current * fraction * 10).rounded() / 10))
            date = date.addingTimeInterval(20 * 60)
        }
        return samples
    }

    // MARK: - Codex

    static let codexPlan = "pro"

    static func codexCredentials(startedAt: Date) -> CodexCredentials {
        CodexCredentials(
            accessToken: codexToken,
            accountId: "demo-codex",
            authMode: "chatgpt",
            lastRefresh: startedAt,
            expiresAt: startedAt.addingTimeInterval(9 * 86_400),
            planType: codexPlan
        )
    }

    static func codexUsage(at now: Date, startedAt: Date) -> CodexUsageResponse {
        let minutes = now.timeIntervalSince(startedAt) / 60
        func window(base: Double, swing: Double, seconds: Int, offset: Double, phase: Double) -> CodexRateWindow {
            let reset = nextReset(after: now, window: TimeInterval(seconds), offsetMinutes: offset)
            let value = min(100, max(0, base + swing * sin(minutes / 11 + phase)))
            return CodexRateWindow(
                usedPercent: value.rounded(),
                limitWindowSeconds: seconds,
                resetAfterSeconds: Int(reset.timeIntervalSince(now)),
                resetAt: Int(reset.timeIntervalSince1970)
            )
        }
        return CodexUsageResponse(
            planType: codexPlan,
            rateLimit: CodexRateLimit(
                allowed: true,
                limitReached: false,
                primaryWindow: window(base: 41, swing: 7, seconds: 5 * 3600, offset: 70, phase: 0),
                secondaryWindow: window(base: 23, swing: 2, seconds: 7 * 86_400, offset: 2_400, phase: 1)
            )
        )
    }

    static let codexHistory = DemoHistoryShape(
        tokensPerHour: 260_000,
        models: [(.codex(model: "gpt-5.3-codex"), 0.8), (.codex(model: "gpt-5.3-codex-spark"), 0.2)],
        projects: ["/demo/acme-api", "/demo/data-pipeline"],
        quietFor: nil
    )

    // MARK: - History

    /// Hourly buckets of a fake account's transcripts in `[start, end)`:
    /// busy on weekday working hours, quieter evenings, near silent nights
    /// and weekends, with a deterministic jitter per hour.
    static func hourlyBuckets(
        shape: DemoHistoryShape,
        seed: String,
        from start: Date,
        to end: Date,
        startedAt: Date,
        calendar: Calendar = .current
    ) -> [HistoryBucket] {
        guard shape.tokensPerHour > 0, !shape.models.isEmpty, start < end else { return [] }
        let quietAfter = shape.quietFor.map { startedAt.addingTimeInterval(-$0) }
        let first = calendar.dateInterval(of: .hour, for: start)?.start ?? start
        var buckets: [HistoryBucket] = []
        var hour = first
        while hour < end {
            defer { hour = hour.addingTimeInterval(3600) }
            guard hour >= start else { continue }
            if let quietAfter, hour >= quietAfter { continue }
            let weight = activity(at: hour, calendar: calendar)
            let jitter = unitNoise(seed + "|" + String(Int(hour.timeIntervalSince1970)))
            let active = Int(Double(shape.tokensPerHour) * weight * (0.35 + 0.65 * jitter))
            guard active > 2_000 else { continue }
            var byModel: [ModelKind: Int] = [:]
            for (model, share) in shape.models {
                byModel[model, default: 0] += Int(Double(active) * share)
            }
            let projectIndex = Int(jitter * Double(shape.projects.count)) % max(shape.projects.count, 1)
            let project = shape.projects.isEmpty ? "/demo" : shape.projects[projectIndex]
            buckets.append(HistoryBucket(
                date: hour,
                tokensByModel: byModel,
                tokensByProject: [project: active],
                sessionsCount: 1 + Int(jitter * 3),
                inputTokens: active / 5,
                outputTokens: active * 3 / 10,
                cacheReadTokens: active * 3,
                cacheCreateTokens: active / 2
            ))
        }
        return buckets
    }

    /// How busy an hour is, 0 to 1.
    private static func activity(at date: Date, calendar: Calendar) -> Double {
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let weekend = weekday == 1 || weekday == 7
        let base: Double
        switch hour {
        case 9..<12, 14..<18: base = 1
        case 12..<14, 18..<21: base = 0.45
        case 21..<24, 7..<9: base = 0.2
        default: base = 0
        }
        return weekend ? base * 0.25 : base
    }

    /// The low 48 bits as twelve hex digits, for a uuid-shaped fake id.
    private static func hex12(_ value: UInt64) -> String {
        let hex = String(value & 0xFFFF_FFFF_FFFF, radix: 16)
        return String(repeating: "0", count: max(0, 12 - hex.count)) + hex
    }

    /// A number in [0, 1) that depends only on the string.
    static func unitNoise(_ text: String) -> Double {
        Double(stableHash(text) % 10_000) / 10_000
    }

    /// FNV-1a, stable across launches (`hashValue` is not).
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }
}

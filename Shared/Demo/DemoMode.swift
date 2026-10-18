import Foundation

/// The multi-account demo: fake Claude accounts and a fake Codex login, for
/// trying every multi-account surface on a Mac with a single real account.
///
/// Off unless the maintainer turns it on by hand, and read once at launch:
///
///     defaults write com.tokeneater.app demo.multiAccount -bool YES
///
/// Off again, everything the demo added is removed at the next launch
/// (`DemoLaunch`):
///
///     defaults delete com.tokeneater.app demo.multiAccount
///
/// The fake accounts run the app's real code from the service seams up: a
/// fake folder (`~/.claude-demo-*`, never created) gets a `DemoTokenProvider`
/// whose token `DemoAPIClient` answers in memory, so its store, shared file,
/// pacing samples, notifications, mode pill, menu bar marker, popover
/// section, dashboard column, Studio layouts and widget index entry are the
/// real ones. Nothing about a fake account reads the Keychain, a credential
/// file or the network. The real main account keeps its real chain.
enum DemoMode {
    static let flagKey = "demo.multiAccount"
    /// The app's defaults as they were when the demo started, restored when
    /// it ends.
    static let snapshotKey = "demo.multiAccount.snapshot"
    /// The widget's accounts index as it was, absent when there was none.
    static let snapshotIndexKey = "demo.multiAccount.snapshotIndex"
    /// Whether `codex.json` existed before the fake Codex login wrote it.
    static let codexFileExistedKey = "demo.multiAccount.codexFileExisted"
    static let startedAtKey = "demo.multiAccount.startedAt"

    static let keys = [flagKey, snapshotKey, snapshotIndexKey, codexFileExistedKey, startedAtKey]

    /// Whether this process runs the demo. Read once, after `DemoLaunch`
    /// has settled the launch, and never again: flipping the switch while
    /// the app runs changes nothing until the next launch. False in the
    /// widget, whose defaults never hold the switch.
    static let isActive: Bool = UserDefaults.standard.bool(forKey: flagKey)

    /// When the demo was turned on. The fixtures' drift and the expired
    /// login's date count from it, so they agree across relaunches.
    static let startedAt: Date = (UserDefaults.standard.object(forKey: startedAtKey) as? Date) ?? Date()

    // MARK: - Seams shared with the real code
    //
    // The only places where code that ships for everyone asks about the
    // demo. Each one answers exactly as before when the demo is off.

    /// Whether a Claude config folder exists, for the account health line.
    /// A demo folder is never created, so it would read as deleted.
    static func configFolderExists(atPath path: String, active: Bool = isActive) -> Bool {
        if active, DemoFixtures.fixture(forFolder: path, home: ClaudeConfigDirResolver.realHome()) != nil {
            return true
        }
        return FileManager.default.fileExists(atPath: path)
    }

    /// The history of a demo folder, generated in memory. Nil for any other
    /// folder, and for every folder when the demo is off.
    static func historyService(
        for root: ClaudeHistoryRoot,
        active: Bool = isActive,
        home: String = ClaudeConfigDirResolver.realHome()
    ) -> SessionHistoryServiceProtocol? {
        guard active else { return nil }
        let folder = root.projectsURL.deletingLastPathComponent().path
        guard let fixture = DemoFixtures.fixture(forFolder: folder, home: home) else { return nil }
        return DemoSessionHistoryService(
            shape: fixture.history,
            seed: fixture.key,
            provider: .claude,
            startedAt: startedAt
        )
    }

    /// The fake Codex login's history, nil when the demo is off.
    static func codexHistoryService(active: Bool = isActive) -> SessionHistoryServiceProtocol? {
        guard active else { return nil }
        return DemoSessionHistoryService(
            shape: DemoFixtures.codexHistory,
            seed: "codex",
            provider: .codex,
            startedAt: startedAt
        )
    }
}

// MARK: - Claude

/// The login of a demo folder, served without reading anything. Built only
/// for a folder `DemoFixtures` knows, and only while the demo runs.
struct DemoTokenProvider: TokenProviderProtocol {
    let fixture: DemoClaudeFixture
    let scope: CredentialScope
    let startedAt: Date

    /// The provider for a demo folder's scope, nil for any other scope.
    static func make(
        scope: CredentialScope,
        home: String = ClaudeConfigDirResolver.realHome(),
        startedAt: Date = DemoMode.startedAt
    ) -> DemoTokenProvider? {
        guard let fixture = DemoFixtures.fixture(forScope: scope, home: home) else { return nil }
        return DemoTokenProvider(fixture: fixture, scope: scope, startedAt: startedAt)
    }

    /// The demo login for a demo folder, the real provider for any other.
    static func orReal(scope: CredentialScope) -> TokenProviderProtocol {
        if let demo = make(scope: scope) { return demo }
        return TokenProvider(scope: scope)
    }

    func currentToken() -> String? {
        fixture.login == .none ? nil : fixture.token
    }

    func hasTokenSource() -> Bool { fixture.login != .none }
    func invalidateToken() {}
    func refreshTokenIfChanged() -> Bool { false }
    var isBootstrapped: Bool { true }
    func bootstrap() throws {}
    func resetConnection() -> String? { currentToken() }
    func reconfigure(scope: CredentialScope) {}

    /// A Keychain read, as the real provider records one: a live login
    /// expiring later today, an expired one, or no item at all.
    var tokenDiagnostic: TokenDiagnostic {
        switch fixture.login {
        case .valid:
            let expiry = startedAt.addingTimeInterval(8 * 3600)
            return TokenDiagnostic(
                source: .keychainCLI,
                keychainFailure: nil,
                matchingKeychainItems: 1,
                tokenExpiresAt: max(expiry, Date().addingTimeInterval(3600)),
                keychainExpiresAt: max(expiry, Date().addingTimeInterval(3600))
            )
        case .expired:
            let expiry = DemoFixtures.expiredAt(startedAt: startedAt)
            return TokenDiagnostic(
                source: .keychainCLI,
                keychainFailure: nil,
                matchingKeychainItems: 1,
                tokenExpiresAt: expiry,
                keychainExpiresAt: expiry
            )
        case .none:
            return TokenDiagnostic(source: nil, keychainFailure: .notFound)
        }
    }
}

/// The main account's provider in the demo: its real one, unless the main
/// account is pointed at a demo folder (the folder picker lists them too),
/// where the demo login answers instead.
final class DemoRoutingTokenProvider: TokenProviderProtocol, @unchecked Sendable {
    private let real: TokenProviderProtocol
    private let home: String

    init(real: TokenProviderProtocol, home: String = ClaudeConfigDirResolver.realHome()) {
        self.real = real
        self.home = home
    }

    private var target: TokenProviderProtocol {
        if let demo = DemoTokenProvider.make(scope: real.scope, home: home) { return demo }
        return real
    }

    func currentToken() -> String? { target.currentToken() }
    func hasTokenSource() -> Bool { target.hasTokenSource() }
    func invalidateToken() { target.invalidateToken() }
    func refreshTokenIfChanged() -> Bool { target.refreshTokenIfChanged() }
    var isBootstrapped: Bool { target.isBootstrapped }
    func bootstrap() throws { try target.bootstrap() }
    var tokenDiagnostic: TokenDiagnostic { target.tokenDiagnostic }
    func resetConnection() -> String? { target.resetConnection() }
    func reconfigure(scope: CredentialScope) { real.reconfigure(scope: scope) }
    var scope: CredentialScope { real.scope }
}

/// Answers the demo's tokens from the fixtures and hands every other token
/// to the real client untouched, so the real main account keeps its real
/// calls while fake accounts make none.
struct DemoAPIClient: APIClientProtocol {
    let real: APIClientProtocol
    var startedAt: Date = DemoMode.startedAt
    /// A short wait before answering, so loading states show as they would.
    var latency: Duration = .milliseconds(250)

    func fetchUsage(token: String, proxyConfig: ProxyConfig?) async throws -> UsageResponse {
        guard let fixture = DemoFixtures.fixture(forToken: token) else {
            return try await real.fetchUsage(token: token, proxyConfig: proxyConfig)
        }
        try await answerDelay()
        try refuseIfExpired(fixture, endpoint: "/api/oauth/usage")
        return DemoFixtures.usage(for: fixture, at: Date(), startedAt: startedAt)
    }

    func fetchProfile(token: String, proxyConfig: ProxyConfig?) async throws -> ProfileResponse {
        guard let fixture = DemoFixtures.fixture(forToken: token) else {
            return try await real.fetchProfile(token: token, proxyConfig: proxyConfig)
        }
        try await answerDelay()
        try refuseIfExpired(fixture, endpoint: "/api/oauth/profile")
        return DemoFixtures.profile(for: fixture)
    }

    func testConnection(token: String, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        guard let fixture = DemoFixtures.fixture(forToken: token) else {
            return await real.testConnection(token: token, proxyConfig: proxyConfig)
        }
        guard fixture.login == .valid else {
            return ConnectionTestResult(success: false, message: String(localized: "error.tokenexpired"))
        }
        return ConnectionTestResult(success: true, message: "OK")
    }

    private func answerDelay() async throws {
        try await Task.sleep(for: latency)
    }

    private func refuseIfExpired(_ fixture: DemoClaudeFixture, endpoint: String) throws {
        guard fixture.login == .valid else {
            throw APIError.tokenExpired(endpoint: endpoint, statusCode: 401)
        }
    }
}

/// The real scanner's folders plus the demo's: one with a login, one
/// without, one signed in to an account already tracked. The real scan
/// still runs, unchanged, for the real folders.
struct DemoConfigDirScanner: ClaudeConfigDirScannerProtocol {
    let real: ClaudeConfigDirScannerProtocol
    var home: String = ClaudeConfigDirResolver.realHome()
    var startedAt: Date = DemoMode.startedAt

    func candidates(excluding trackedPaths: Set<String>) -> [ConfigDirCandidate] {
        let excluded = Set(trackedPaths.map { ClaudeConfigDirResolver.normalize($0, home: home) })
        let fakes = DemoFixtures.claude
            .filter { !excluded.contains($0.folderPath(home: home)) }
            .map(candidate(for:))
        let fakePaths = Set(fakes.map(\.path))
        let reals = real.candidates(excluding: trackedPaths).filter { !fakePaths.contains($0.path) }
        return fakes + reals
    }

    func inspect(path: String) -> ConfigDirCandidate {
        guard let fixture = DemoFixtures.fixture(forFolder: path, home: home) else {
            return real.inspect(path: path)
        }
        return candidate(for: fixture)
    }

    private func candidate(for fixture: DemoClaudeFixture) -> ConfigDirCandidate {
        let path = fixture.folderPath(home: home)
        let rank = Double(DemoFixtures.claude.firstIndex(of: fixture) ?? 0)
        return ConfigDirCandidate(
            path: path,
            displayPath: ClaudeConfigDirResolver.displayPath(path, home: home),
            matchedService: fixture.login == .none ? nil : fixture.service(home: home),
            hasCredentialsFile: false,
            lastActivity: fixture.login == .none ? nil : startedAt.addingTimeInterval(-3600 * (rank + 1)),
            exists: true
        )
    }
}

// MARK: - Codex

/// The fake Codex login: a ChatGPT Pro sign-in that never expires during
/// the demo. Reads no `auth.json`.
struct DemoCodexTokenProvider: CodexTokenProviderProtocol {
    var startedAt: Date = DemoMode.startedAt

    func currentCredentials() -> CodexCredentials? { DemoFixtures.codexCredentials(startedAt: startedAt) }
    func invalidate() {}
    func refreshIfChanged() -> Bool { false }

    var authState: CodexAuthState {
        let credentials = DemoFixtures.codexCredentials(startedAt: startedAt)
        return .chatgpt(
            accountId: credentials.accountId,
            planType: credentials.planType,
            expiresAt: credentials.expiresAt
        )
    }

    var codexHomeURL: URL {
        URL(fileURLWithPath: ClaudeConfigDirResolver.realHome()).appendingPathComponent(".codex-demo")
    }

    var authFileURL: URL { codexHomeURL.appendingPathComponent("auth.json") }
}

/// Answers the fake Codex login from the fixtures. Makes no call.
struct DemoCodexAPIClient: CodexAPIClientProtocol {
    var startedAt: Date = DemoMode.startedAt
    var latency: Duration = .milliseconds(250)

    func fetchUsage(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async throws -> CodexUsageResponse {
        try await Task.sleep(for: latency)
        return DemoFixtures.codexUsage(at: Date(), startedAt: startedAt)
    }

    func testConnection(credentials: CodexCredentials, proxyConfig: ProxyConfig?) async -> ConnectionTestResult {
        ConnectionTestResult(success: true, message: "OK")
    }
}

// MARK: - History

/// A fake account's transcripts, generated for the asked range. Writes no
/// cache: nothing about it touches the disk.
struct DemoSessionHistoryService: SessionHistoryServiceProtocol {
    let shape: DemoHistoryShape
    let seed: String
    let provider: MetricProvider
    let startedAt: Date

    func loadHistory(range: HistoryRange) async throws -> [HistoryBucket] {
        let now = Date()
        let start = range == .sevenDays
            ? ChartDomainCalculator.domain(range: range, now: now).start
            : now.addingTimeInterval(-range.seconds)
        let hourly = DemoFixtures.hourlyBuckets(shape: shape, seed: seed, from: start, to: now, startedAt: startedAt)
        try Task.checkCancellation()
        guard !range.isHourly else { return hourly }
        let calendar = Calendar.current
        var days: [Date: HistoryBucket] = [:]
        for bucket in hourly {
            let day = calendar.startOfDay(for: bucket.date)
            days[day] = HistoryBucket.merging(days[day] ?? .empty, bucket, date: day)
        }
        return days.values.sorted { $0.date < $1.date }
    }

    func loadPreviousPeriodActiveTokens(range: HistoryRange) async throws -> [MetricProvider: Int] {
        let now = Date()
        let currentStart = range == .sevenDays
            ? ChartDomainCalculator.domain(range: range, now: now).start
            : now.addingTimeInterval(-range.seconds)
        let previousStart = currentStart.addingTimeInterval(-now.timeIntervalSince(currentStart))
        let buckets = DemoFixtures.hourlyBuckets(
            shape: shape,
            seed: seed,
            from: previousStart,
            to: currentStart,
            startedAt: startedAt
        )
        let total = buckets.reduce(0) { $0 + $1.totalActive }
        return total > 0 ? [provider: total] : [:]
    }
}

// MARK: - Notifications

/// Notification state kept in memory, for the demo's sample alerts: they
/// show the real wording without moving any account's real alert state.
final class InMemoryNotificationStateStore: NotificationStateStore {
    private var levels: [String: Int] = [:]
    private var pacing: [String: String] = [:]
    private var resets: [String: Date] = [:]
    private var utilizations: [String: Double] = [:]
    private var tokenSent = false
    private var loginExpired: Date?
    private var codexExpired: Date?

    func hasBaseline(forKey key: String) -> Bool { levels[key] != nil }
    func lastLevel(forKey key: String) -> Int { levels[key] ?? 0 }
    func setLastLevel(_ value: Int, forKey key: String) { levels[key] = value }
    func lastPacing(forKey key: String) -> String? { pacing[key] }
    func setLastPacing(_ value: String, forKey key: String) { pacing[key] = value }
    func lastResetsAt(forKey key: String) -> Date? { resets[key] }
    func setLastResetsAt(_ date: Date, forKey key: String) { resets[key] = date }
    func tokenAlertSent() -> Bool { tokenSent }
    func setTokenAlertSent(_ sent: Bool) { tokenSent = sent }
    func loginExpiredAlertedFor() -> Date? { loginExpired }
    func setLoginExpiredAlertedFor(_ expiresAt: Date) { loginExpired = expiresAt }
    func lastUtilization(forKey key: String) -> Double? { utilizations[key] }
    func setLastUtilization(_ value: Double, forKey key: String) { utilizations[key] = value }
    func codexTokenExpiredFiredAt() -> Date? { codexExpired }
    func setCodexTokenExpiredFiredAt(_ date: Date) { codexExpired = date }
}

/// The demo's sample alerts: one account's real threshold and expired-login
/// notifications, built by the real `NotificationService` under that
/// account's scope (identifiers, thread, subtitle, login command), on fresh
/// in-memory state so they always fire and leave nothing behind.
enum DemoNotifications {
    static func sendThresholdSample(scope: NotificationScope, thresholds: UsageThresholds, center: NotificationCenterProtocol = LiveNotificationCenter()) {
        let service = NotificationService(center: center, stateStore: InMemoryNotificationStateStore(), scope: scope)
        let reset = Date().addingTimeInterval(2 * 3600)
        let calm = MetricSnapshot(pct: 10, resetsAt: reset, windowDuration: 5 * 3600)
        let hot = MetricSnapshot(pct: max(thresholds.criticalPercent + 4, 90), resetsAt: reset, windowDuration: 5 * 3600)
        let idle = MetricSnapshot(pct: 0, resetsAt: nil, windowDuration: 7 * 86_400)
        let toggles = sampleToggles(thresholds: thresholds)
        // First pass sets the baseline, the second crosses the threshold.
        service.evaluate(fiveHour: calm, sevenDay: idle, sonnet: nil, fable: idle, sessionPacing: nil,
                         weeklyPacing: nil, extraUsage: nil, toggles: toggles)
        service.evaluate(fiveHour: hot, sevenDay: idle, sonnet: nil, fable: idle, sessionPacing: nil,
                         weeklyPacing: nil, extraUsage: nil, toggles: toggles)
    }

    static func sendLoginExpiredSample(scope: NotificationScope, thresholds: UsageThresholds, center: NotificationCenterProtocol = LiveNotificationCenter()) {
        let service = NotificationService(center: center, stateStore: InMemoryNotificationStateStore(), scope: scope)
        service.notifyLoginExpired(
            since: Date().addingTimeInterval(-2 * 3600),
            toggles: sampleToggles(thresholds: thresholds)
        )
    }

    /// Every Claude alert on, Smart Color off so the threshold is the plain
    /// percentage one.
    static func sampleToggles(thresholds: UsageThresholds) -> NotificationToggles {
        NotificationToggles(
            masterEnabled: true,
            claudeEnabled: true,
            trackFiveHour: true,
            trackWeekly: true,
            trackSonnet: false,
            trackFable: true,
            sendRecovery: false,
            pacingHot: false,
            pacingWarning: false,
            resetReminderSession: false,
            resetReminderWeekly: false,
            resetReminderSessionOffsetMinutes: 15,
            resetReminderWeeklyOffsetMinutes: 60,
            extraCredits: false,
            tokenExpired: true,
            smartColorEnabled: false,
            smartColorProfile: .default,
            pacingMargin: 10,
            thresholds: thresholds,
            vendorDegraded: false,
            vendorRestored: false
        )
    }
}

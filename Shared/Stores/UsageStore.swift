import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var fiveHourPct: Int = 0
    @Published var sevenDayPct: Int = 0
    @Published var sonnetPct: Int = 0
    @Published var fiveHourReset: String = ""
    @Published var fiveHourResetAbsolute: String = ""
    @Published var sevenDayReset: String = ""
    @Published var sevenDayResetAbsolute: String = ""
    @Published var pacingDelta: Int = 0
    @Published var pacingZone: PacingZone = .onTrack
    @Published var pacingResult: PacingResult?
    @Published var fiveHourPacing: PacingResult?
    @Published var sonnetPacing: PacingResult?
    @Published var fablePacing: PacingResult?
    /// Dated 5h-session utilization readings over the current window, powering
    /// the hero pacing graph's real trajectory (#240). Appended on each live
    /// refresh, persisted to UserDefaults so it survives relaunches.
    @Published var sessionSamples: [PacingSample] = []
    @Published var lastUpdate: Date?
    @Published var isLoading = false
    @Published var errorState: AppErrorState = .none {
        didSet {
            // The expired-login escalation only means something while the
            // token is the problem; any other outcome ends the episode.
            if errorState != .tokenUnavailable, loginExpiredSince != nil {
                loginExpiredSince = nil
            }
        }
    }
    @Published var hasConfig = false

    /// Set when an unauthorized response is explained by something other than
    /// an expired token, so the surfaces can say what actually happened
    /// instead of sending the user to relaunch Claude Code for nothing (#273).
    @Published private(set) var authFailureHint: String?

    /// Where the token in use came from, for the diagnostic report.
    var tokenDiagnostic: TokenDiagnostic { tokenProvider.tokenDiagnostic }

    /// When the Claude Code login expired, once it has been expired for over
    /// an hour with nothing renewing it (`TokenExpiryPolicy`). The calm
    /// "waiting" state is right for the routine lag before the next CLI run,
    /// but someone who works in the Claude desktop app may not run the CLI
    /// for a day, and the app used to sit calm over frozen numbers all that
    /// time (#268). Set, it turns the popover and the dashboard notice into
    /// an actionable explanation. Nil whenever the app is not in
    /// `.tokenUnavailable`, and when `authFailureHint` already names a
    /// different cause.
    @Published private(set) var loginExpiredSince: Date?
    @Published var opusPct: Int = 0
    @Published var coworkPct: Int = 0
    @Published var fablePct: Int = 0
    @Published var oauthAppsPct: Int = 0
    @Published var hasOpus: Bool = false
    @Published var hasCowork: Bool = false
    @Published var hasFable: Bool = false
    /// True when the response carries a Sonnet weekly limit (a flat
    /// `seven_day_sonnet` utilization or a `limits[]` entry). Anthropic no
    /// longer sends one to most accounts, so every Sonnet surface (menu bar,
    /// popover, dashboard, widget, alerts) is gated on this.
    @Published var hasSonnet: Bool = false
    @Published var fableReset: String = ""
    @Published var fableResetAbsolute: String = ""
    @Published var sonnetReset: String = ""
    @Published var sonnetResetAbsolute: String = ""
    @Published var extraUsage: ExtraUsage?
    @Published var planType: PlanType = .unknown
    @Published var rateLimitTier: String?
    @Published var organizationName: String?
    /// The login's email as "m•••@acme.com", for telling accounts apart in
    /// Settings. Memory only: never persisted, never in a shared file or the
    /// diagnostic report.
    @Published private(set) var maskedEmail: String?
    @Published private(set) var lastUsage: UsageResponse?
    /// Snapshot of the most recent API failure for the diagnostic report.
    /// Cleared on every successful refresh.
    @Published private(set) var lastAPIError: LastAPIError?

    var hasError: Bool { errorState != .none }

    var isDisconnected: Bool {
        errorState == .tokenUnavailable
    }

    /// The token is unavailable (expired, or momentarily unreadable) but we
    /// already have a usage snapshot to show. This is the routine "Claude Code
    /// hasn't refreshed the token yet" case, not a broken/unconfigured app, so
    /// the UI surfaces it calmly (dimmed last-known data + "waiting" copy)
    /// instead of the alarming re-auth banner. When there's no prior snapshot
    /// (fresh install, never connected) `isDisconnected` stays the right signal.
    var isAwaitingRefresh: Bool {
        errorState == .tokenUnavailable && lastUsage != nil
    }

    /// When the numbers on screen were fetched, while they are the last known
    /// ones of a login that no longer answers; nil while they are live. The
    /// surfaces then draw them greyed and dated ("last numbers 2 days ago")
    /// rather than in risk colours with a countdown that may already have
    /// passed, so a frozen snapshot never reads as a fresh one.
    var lastNumbersDate: Date? {
        isAwaitingRefresh ? lastUpdate : nil
    }

    /// True when the paid Extra Credits pool is provisioned and turned on for
    /// this account. Mirrors `hasOpus`: drives whether the metric
    /// can be pinned to the menu bar and shown in the widgets.
    var hasExtraCredits: Bool { extraUsage?.isEnabled == true }

    /// Extra Credits utilization as a whole-number percentage (see
    /// `ExtraUsage.percent`). 0 when the pool is absent.
    var extraCreditsPct: Int { extraUsage?.percent ?? 0 }

    /// The amount spent when the Extra Credits pool has no monthly limit, nil
    /// otherwise (see `ExtraUsage.uncappedSpendText`). A percentage of no limit
    /// is always 0, so the menu bar and the popover show this instead.
    var extraCreditsUncappedSpend: String? { extraUsage?.uncappedSpendText }

    /// Whether that uncapped amount is above zero, which turns it from the
    /// neutral colour to the warning colour (see `ExtraUsage.hasUncappedSpend`).
    var extraCreditsUncappedHasSpend: Bool { extraUsage?.hasUncappedSpend == true }

    var pacingMargin: Int = 10
    /// Workweek pacing schedule (from settings). Wired by StatusBarController.
    /// Drives whether off-days count toward the expected pace.
    var pacingSchedule: PacingSchedule = .rolling
    /// Base refresh interval in seconds (from settings, default 300)
    var refreshIntervalSeconds: TimeInterval = 300

    private let repository: UsageRepositoryProtocol
    private let tokenProvider: TokenProviderProtocol
    private let sharedFileService: SharedFileServiceProtocol
    private let notificationService: NotificationServiceProtocol
    private var refreshTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    /// The usage request on the wire, cancelled when the store stops, moves
    /// to another folder or is retired.
    private var inFlightFetch: Task<UsageResponse, Error>?

    /// Bumped whenever what the store reads stops being what it was: the
    /// account is paused, removed, switched off, or moved to another folder.
    /// A refresh compares it after every `await` and drops its result when
    /// it moved, so an answer that left before the change never writes the
    /// shared file, the samples, the screen or an alert.
    private var generation = 0
    /// One refresh at a time. Not `isLoading`, which only covers the network
    /// part and repaints the surfaces.
    private var refreshing = false
    /// Set once an added account is removed: nothing about it runs again.
    private(set) var isRetired = false

    /// Current adaptive speed for rate limiting
    private(set) var currentSpeed: RefreshSpeed = .normal

    /// When fast mode was activated (resets to normal after 10 minutes)
    private var fastModeStart: Date?

    /// Retry-After date from last 429 response
    private(set) var retryAfterDate: Date?

    /// Number of consecutive 429s we've received. Drives the exponential
    /// backoff because anthropic's /api/oauth/usage endpoint returns 429 with
    /// no useful Retry-After header (known issue on their side, see
    /// anthropics/claude-code#31637 and #31021). Reset on every success.
    private var consecutiveRateLimits: Int = 0

    /// Effective interval based on current speed + user setting
    var effectiveInterval: TimeInterval {
        RateLimitBackoff.effectiveInterval(speed: currentSpeed, baseInterval: refreshIntervalSeconds)
    }

    var proxyConfig: ProxyConfig?

    /// Closure that returns the current notification toggles bundle. Wired by
    /// `StatusBarController` at bootstrap once SettingsStore is available so
    /// the store can fire notifications based on the latest user-facing toggles
    /// without owning a direct SettingsStore reference.
    var notifTogglesProvider: (() -> NotificationToggles?)?

    var cachedUsage: CachedUsage? {
        sharedFileService.cachedUsage
    }

    // MARK: - Identity (several Claude accounts)

    /// Decides whether the login behind a token is this account's. Set by
    /// `AccountsStore` only while two or more accounts are tracked: with one,
    /// the store follows whatever login is active (cswap, #153) and never
    /// fetches a profile on the refresh path.
    var identityGate: ((String) -> IdentityVerdict)? {
        didSet {
            guard identityGate == nil else { return }
            verifiedToken = nil
            if identityState != .unchecked { identityState = .unchecked }
        }
    }

    /// Hands every fetched profile's identity digest to `AccountsStore`, which
    /// keeps the main account's digest current while it is the only one.
    var onIdentityDigest: ((String) -> Void)?

    /// Where the identity check stands. Stays `.unchecked` with one account.
    @Published private(set) var identityState: IdentityState = .unchecked

    /// The token whose login the gate last accepted. A rotation (a new token
    /// for the same folder) is checked again before its numbers are written.
    private var verifiedToken: String?

    /// The identity digest of the last profile fetched, for `AccountsStore`
    /// to compare a newly connected folder against.
    private(set) var lastIdentityDigest: String?

    /// Where this store's token may come from.
    var credentialScope: CredentialScope { tokenProvider.scope }

    /// What renews this store's login once it has expired, for the popover
    /// banner and the dashboard notice.
    var loginExpiredHint: String {
        Self.loginExpiredHint(scope: credentialScope, home: ClaudeConfigDirResolver.realHome())
    }

    /// A plain `claude` renews only the login of `~/.claude`, so a config
    /// folder (an added account, or the main account moved there, #294) is
    /// named in the command. The default chain keeps the 6.0 wording.
    nonisolated static func loginExpiredHint(scope: CredentialScope, home: String) -> String {
        guard let command = renewCommand(scope: scope, home: home) else {
            return String(localized: "error.login.expired.hint")
        }
        return String(format: String(localized: "error.login.expired.hint.dir"), command)
    }

    /// The command that renews a config folder's login, nil for the default
    /// chain, where a plain `claude` or the Claude desktop app does it.
    nonisolated static func renewCommand(scope: CredentialScope, home: String) -> String? {
        guard case .configDir(let path, _) = scope else { return nil }
        return ClaudeConfigDirResolver.loginCommand(forConfigDir: path, home: home)
    }

    init(
        repository: UsageRepositoryProtocol = UsageRepository(),
        tokenProvider: TokenProviderProtocol = TokenProvider.forMainAccount(),
        sharedFileService: SharedFileServiceProtocol = SharedFileService(),
        notificationService: NotificationServiceProtocol = NotificationService(),
        sessionSamplesKey: String = "sessionPacingSamples",
        reloadWidgets: @escaping @MainActor () -> Void = { WidgetReloader.scheduleReload() }
    ) {
        self.sessionSamplesKey = sessionSamplesKey
        self.repository = repository
        self.tokenProvider = tokenProvider
        self.sharedFileService = sharedFileService
        self.notificationService = notificationService
        self.reloadWidgets = reloadWidgets
        self.sessionSamples = Self.loadSessionSamples(key: sessionSamplesKey)
    }

    /// Reloads the widgets that read this store's shared file. The main
    /// account reloads the existing kinds; an added account passes a no-op,
    /// since none of those kinds reads its file.
    private let reloadWidgets: @MainActor () -> Void

    // MARK: - Session pacing samples (#240)

    private let sessionSamplesKey: String

    private static func loadSessionSamples(key: String) -> [PacingSample] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PacingSample].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Records the live 5h utilization as a dated sample and persists the
    /// windowed buffer. Only called on a real successful sync (never on the
    /// cached-load path), so a relaunch doesn't inject a stale "now" point.
    private func appendSessionSample(from usage: UsageResponse) {
        guard let bucket = usage.fiveHour, let reset = bucket.resetsAtDate else { return }
        sessionSamples = PacingSampleBuffer.append(
            sessionSamples,
            utilization: bucket.utilization,
            resetDate: reset,
            windowDuration: 5 * 3600,
            now: Date()
        )
        if let data = try? JSONEncoder().encode(sessionSamples) {
            UserDefaults.standard.set(data, forKey: sessionSamplesKey)
        }
    }

    func refresh(thresholds: UsageThresholds = .default, force: Bool = false) async {
        // Prevent concurrent refreshes
        guard !refreshing, !isRetired else { return }
        refreshing = true
        let started = generation
        defer { if generation == started { refreshing = false } }

        // A refresh can come before the cache was ever loaded (a token
        // change, a wake, an added account still waiting its turn). Showing
        // the last numbers first means a refused login keeps them on screen,
        // dated, instead of a blank 0% that looks like a fresh reading.
        if lastUsage == nil { loadCached() }

        // Resolve token, off the main thread: a `security` read can take
        // seconds when the Keychain is slow to answer.
        let resolved = await readToken()
        guard generation == started else { return }
        guard let token = resolved else {
            hasConfig = false
            errorState = .tokenUnavailable
            updateLoginExpiry()
            return
        }
        hasConfig = true

        // Decay fast mode after 10 minutes
        if currentSpeed == .fast, let start = fastModeStart,
           Date().timeIntervalSince(start) > 600 {
            currentSpeed = .normal
            fastModeStart = nil
        }

        // Interval check using currentSpeed
        if !force, let last = lastUpdate,
           Date().timeIntervalSince(last) < effectiveInterval {
            return
        }

        // Respect Retry-After from previous 429 response
        if !force, let retryAfter = retryAfterDate, Date() < retryAfter {
            return
        }

        isLoading = true
        defer { if generation == started { isLoading = false } }

        do {
            // With several accounts, a login is checked before its numbers
            // are written anywhere, so one account's usage can never land
            // under another's name. Nothing runs here with a single account.
            // A login whose profile is refused is not checked, so it takes
            // the 401 path below without fetching any usage.
            if identityGate != nil {
                switch await verifyIdentity(token: token, generation: started) {
                case .proceed: break
                case .stop: return
                case .unauthorized(let error): throw error
                }
            }
            let usage = try await fetchUsage(token: token)
            guard generation == started else { return }
            applySuccess(usage: usage)
        } catch let error as APIError {
            guard generation == started else { return }
            lastAPIError = error.diagnosticSnapshot
            switch error {
            case .tokenExpired, .noToken:
                // Invalidate cached token so next read re-checks Keychain for a fresh one
                tokenProvider.invalidateToken()
                // Retry once with a fresh token
                let fresh = await readToken()
                guard generation == started else { return }
                if let freshToken = fresh, freshToken != token {
                    var check = IdentityCheck.proceed
                    if identityGate != nil {
                        check = await verifyIdentity(token: freshToken, generation: started)
                    }
                    guard generation == started else { return }
                    switch check {
                    case .stop:
                        return
                    case .unauthorized:
                        break
                    case .proceed:
                        do {
                            let usage = try await fetchUsage(token: freshToken)
                            guard generation == started else { return }
                            applySuccess(usage: usage)
                            return
                        } catch {
                            // Retry also failed - fall through to set error
                            guard generation == started else { return }
                        }
                    }
                }
                errorState = .tokenUnavailable
                // The retry above already re-read the sources, so the
                // diagnostic describes the token that just failed.
                authFailureHint = tokenProvider.tokenDiagnostic.authFailureHint
                let now = Date()
                updateLoginExpiry(now: now)
                if let toggles = notifTogglesProvider?() {
                    if let since = loginExpiredSince {
                        notificationService.notifyLoginExpired(since: since, toggles: toggles)
                    } else if !isWithinRefreshLag(now: now) {
                        notificationService.notifyTokenExpired(toggles: toggles)
                    }
                }
            case .rateLimited(let retryAfter, _, _):
                currentSpeed = .slow
                // /api/oauth/usage returns 429 with Retry-After: 0 (or no header)
                // when the throttle kicks in. Anthropic has known issues making
                // this endpoint return persistent 429s for hours with no useful
                // Retry-After (see anthropics/claude-code#31637 + #31021).
                //
                // Strategy: if the server gives us a real positive Retry-After
                // we honor it. Otherwise use exponential backoff capped at 6h.
                // Earlier passes (30 min, 1h, 2h, 4h) recover quickly when the
                // throttle lifts on its own.
                let result = RateLimitBackoff.nextRetryDate(
                    consecutiveRateLimits: consecutiveRateLimits,
                    serverRetryAfter: retryAfter
                )
                consecutiveRateLimits = result.consecutiveRateLimits
                retryAfterDate = result.date
                errorState = .rateLimited
            default:
                errorState = .networkError
            }
        } catch {
            guard generation == started else { return }
            lastAPIError = LastAPIError(
                httpStatusCode: nil,
                retryAfterHeader: nil,
                endpoint: "(unknown)",
                timestamp: Date(),
                underlyingError: error.localizedDescription
            )
            errorState = .networkError
        }
    }

    /// The store's token, read off the main thread. `TokenProvider` answers
    /// from memory when it can; when it cannot it runs `security`, which a
    /// locked or slow Keychain can hold for seconds, once per account.
    private func readToken() async -> String? {
        let provider = tokenProvider
        return await Task.detached(priority: .utility) { provider.currentToken() }.value
    }

    /// The usage call, kept so stopping the store can cancel it. A
    /// cancelled caller cancels it too.
    private func fetchUsage(token: String) async throws -> UsageResponse {
        let repository = self.repository
        let proxy = proxyConfig
        let task = Task { try await repository.fetchUsage(token: token, proxyConfig: proxy) }
        inFlightFetch = task
        defer { if inFlightFetch == task { inFlightFetch = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private enum IdentityCheck {
        case proceed
        case stop
        /// The profile call refused the token: the 401 path takes over.
        case unauthorized(APIError)
    }

    /// Asks the gate about the login behind `token`, fetching its profile
    /// once per token. The profile is taken in (plan, organization, masked
    /// email) only once the gate accepted it, so an account in conflict
    /// never shows another login's facts. A profile that cannot be fetched
    /// keeps the last numbers and writes nothing until a later tick gets an
    /// answer.
    private func verifyIdentity(token: String, generation started: Int) async -> IdentityCheck {
        guard identityGate != nil else { return .proceed }
        guard token != verifiedToken else { return .proceed }
        do {
            let profile = try await repository.fetchProfile(token: token, proxyConfig: proxyConfig)
            guard generation == started, let gate = identityGate else { return .stop }
            let verdict = gate(Self.identityDigest(of: profile))
            guard verdict == .accepted else {
                identityState = .conflict(verdict)
                return .stop
            }
            applyProfile(profile)
            verifiedToken = token
            identityState = .verified
            return .proceed
        } catch let error as APIError {
            guard generation == started else { return .stop }
            switch error {
            case .tokenExpired, .noToken:
                return .unauthorized(error)
            default:
                identityState = .pending
                return .stop
            }
        } catch {
            guard generation == started else { return .stop }
            identityState = .pending
            return .stop
        }
    }

    /// Re-evaluates `loginExpiredSince` against the token in use. Called each
    /// time a refresh lands in `.tokenUnavailable`, which the auto-refresh
    /// tick does every few minutes, so the state flips once the hour is up
    /// without needing an event of its own.
    private func updateLoginExpiry(now: Date = Date()) {
        let since = errorState == .tokenUnavailable && authFailureHint == nil
            ? TokenExpiryPolicy.staleSince(expiresAt: tokenProvider.tokenDiagnostic.loginExpiresAt, now: now)
            : nil
        // Assigned only on change: this runs on every failing tick, and each
        // write to a published property repaints every surface observing it.
        if since != loginExpiredSince { loginExpiredSince = since }
    }

    /// The token expired recently and nothing else explains the 401: the
    /// ordinary wait for Claude Code's next run, during which the app stays
    /// quiet rather than alerting about something that fixes itself.
    private func isWithinRefreshLag(now: Date) -> Bool {
        authFailureHint == nil
            && loginExpiredSince == nil
            && TokenExpiryPolicy.isExpired(tokenProvider.tokenDiagnostic.loginExpiresAt, now: now)
    }

    /// Only refreshes if lastUpdate is older than 120 seconds (for wake handler)
    func refreshIfStale(thresholds: UsageThresholds = .default) async {
        guard lastUpdate == nil || Date().timeIntervalSince(lastUpdate!) > 120 else { return }
        await refresh(thresholds: thresholds, force: true)
    }

    /// Switch to fast mode for FSEvents token changes
    func switchToFastMode() {
        currentSpeed = .fast
        fastModeStart = Date()
    }

    /// Called when the token file changes on disk or the user taps "Retry now".
    /// Invalidates the cached token so the next refresh reads a fresh one,
    /// and clears the rate-limit backoff so the refresh actually fires.
    func handleTokenChange() {
        tokenProvider.invalidateToken()
        retryAfterDate = nil
        switchToFastMode()
    }

    /// Detects an OAuth token rotation that the file watcher cannot see: on
    /// modern macOS the active token lives in the Keychain, so a `cswap` /
    /// `claude login` account swap rotates it with no filesystem event and the
    /// cached token (hence the displayed usage and plan badge) keeps belonging
    /// to the previous account until a 401. Polling the token source on each
    /// auto-refresh tick closes that gap. When a rotation is detected, the
    /// stale state is dropped: clear the rate-limit backoff, force a profile
    /// re-fetch, and switch to fast mode so the new account's data shows up
    /// promptly. Returns true when the caller should force a usage refresh.
    func reconcileTokenIfChanged() async -> Bool {
        guard !isRetired else { return false }
        let provider = tokenProvider
        let started = generation
        let rotated = await Task.detached(priority: .utility) { provider.refreshTokenIfChanged() }.value
        guard rotated, generation == started else { return false }
        retryAfterDate = nil
        consecutiveRateLimits = 0
        lastProfileFetch = nil
        switchToFastMode()
        return true
    }

    func loadCached() {
        if let cached = cachedUsage {
            updateUI(from: cached.usage)
            lastUpdate = cached.fetchDate
        }
    }

    func reloadConfig(thresholds: UsageThresholds = .default) {
        guard !isRetired else { return }
        loadCached()
        notificationService.requestPermission()
        reloadWidgets()
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let token = await self.readToken()
            guard !Task.isCancelled else { return }
            self.hasConfig = token != nil
            self.errorState = token != nil ? .none : .tokenUnavailable
            await self.refresh(thresholds: thresholds, force: true)
            // Fetch the profile right after the first usage refresh so the
            // plan badge (PRO / MAX / TEAM) shows up immediately instead of
            // waiting 10 minutes for the auto-refresh cycle. `refreshProfile`
            // is internally throttled to 5 min, so this is safe to call on
            // every reload.
            await self.refreshProfile()
        }
    }

    func startAutoRefresh(interval: TimeInterval = 600, thresholds: UsageThresholds = .default) {
        autoRefreshTask?.cancel()
        guard !isRetired else { return }
        autoRefreshTask = Task { [weak self] in
            // Wait first - reloadConfig already triggers an initial refresh
            try? await Task.sleep(for: .seconds(interval))
            // Fetch profile once on first cycle (deferred from startup to save rate limit)
            if let self { await self.refreshProfile() }
            while !Task.isCancelled {
                guard let self else { return }
                // Catch account swaps (cswap / claude login) the file watcher
                // misses because the token rotates in the Keychain.
                let rotated = await self.reconcileTokenIfChanged()
                await self.refresh(thresholds: thresholds, force: rotated)
                if rotated { await self.refreshProfile() }
                let delay = self.effectiveInterval
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Stops the loop and drops whatever was in flight: a refresh that
    /// left before writes nothing when it comes back.
    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        abandonInFlightWork()
    }

    /// Stops the store for good, for an account that was removed: nothing
    /// in flight writes its file, its samples or an alert any more, and no
    /// call can start it again.
    func retire() {
        isRetired = true
        stopAutoRefresh()
        identityGate = nil
        notifTogglesProvider = nil
        onIdentityDigest = nil
    }

    private func abandonInFlightWork() {
        refreshTask?.cancel()
        refreshTask = nil
        inFlightFetch?.cancel()
        inFlightFetch = nil
        generation += 1
        refreshing = false
        if isLoading { isLoading = false }
    }

    func reauthenticate() async {
        await refresh(force: true)
    }

    func testConnection() async -> ConnectionTestResult {
        guard let token = await readToken() else {
            return ConnectionTestResult(success: false, message: String(localized: "error.notoken"))
        }
        do {
            _ = try await repository.testConnection(token: token, proxyConfig: proxyConfig)
            return ConnectionTestResult(success: true, message: "OK")
        } catch {
            return ConnectionTestResult(success: false, message: error.localizedDescription)
        }
    }

    /// Unbinds and rebinds the Claude connection without touching a single
    /// preference: drops the cached token and the cached decryption key,
    /// forgets the error state the app was stuck in, re-reads every source and
    /// tests it. Asked for by people who were reinstalling the whole app, and
    /// losing their layouts and themes with it, to recover a connection that a
    /// stale cache had broken (#268).
    func resetConnection(thresholds: UsageThresholds = .default) async -> ConnectionTestResult {
        errorState = .none
        authFailureHint = nil
        lastAPIError = nil
        hasConfig = false
        retryAfterDate = nil
        consecutiveRateLimits = 0
        currentSpeed = .fast
        sharedFileService.invalidateCache()
        let provider = tokenProvider
        _ = await Task.detached(priority: .userInitiated) { provider.resetConnection() }.value

        let result = await connectAutoDetect()
        if result.success {
            await refresh(thresholds: thresholds, force: true)
        }
        return result
    }

    func connectAutoDetect() async -> ConnectionTestResult {
        guard let token = await readToken() else {
            return ConnectionTestResult(
                success: false,
                message: tokenProvider.tokenDiagnostic.authFailureHint
                    ?? String(localized: "error.notoken")
            )
        }
        do {
            _ = try await repository.testConnection(token: token, proxyConfig: proxyConfig)
            hasConfig = true
            authFailureHint = nil
            return ConnectionTestResult(success: true, message: "OK")
        } catch {
            // "Your token expired, relaunch Claude Code" is only the truth when
            // the token we sent is the one Claude Code refreshes. When the
            // Keychain refused us and this came from a file, that advice sends
            // the user somewhere nothing will change (#273).
            return ConnectionTestResult(
                success: false,
                message: tokenProvider.tokenDiagnostic.authFailureHint ?? error.localizedDescription
            )
        }
    }

    private var lastProfileFetch: Date?

    func refreshProfile() async {
        guard !isRetired else { return }
        let started = generation
        guard let token = await readToken(), generation == started else { return }
        // With several accounts, only a login the gate accepted shows its
        // profile; a rotated token waits for the refresh path to check it.
        if identityGate != nil, token != verifiedToken { return }
        // Throttle: profile rarely changes, skip if fetched less than 5min ago
        if let last = lastProfileFetch, Date().timeIntervalSince(last) < 300 { return }
        do {
            let profile = try await repository.fetchProfile(token: token, proxyConfig: proxyConfig)
            guard generation == started else { return }
            if identityGate != nil, token != verifiedToken { return }
            applyProfile(profile)
        } catch {
            // Profile fetch failure is non-critical - don't update errorState
        }
    }

    /// Takes in a fetched profile and returns its identity digest, after
    /// handing it to `onIdentityDigest`. The uuids go no further than here.
    @discardableResult
    private func applyProfile(_ profile: ProfileResponse) -> String {
        planType = PlanType(from: profile.account, organization: profile.organization)
        rateLimitTier = profile.organization?.rateLimitTier
        organizationName = profile.organization?.name
        let masked = ClaudeConfigDirResolver.maskEmail(profile.account.email)
        if masked != maskedEmail { maskedEmail = masked }
        lastProfileFetch = Date()
        let digest = Self.identityDigest(of: profile)
        lastIdentityDigest = digest
        onIdentityDigest?(digest)
        return digest
    }

    nonisolated static func identityDigest(of profile: ProfileResponse) -> String {
        ClaudeConfigDirResolver.identityDigest(
            accountUUID: profile.account.uuid,
            organizationUUID: profile.organization?.uuid
        )
    }

    /// The digest of the login this store reads right now, for refusing a
    /// second copy of this account when another folder is connected. Never
    /// answered from memory: the sources are read again first, since a
    /// cswap or a `claude /login` changes the login with no event, then the
    /// profile is fetched. Nil when there is no token or the profile cannot
    /// be fetched, which `AccountsStore.connect` turns into a refusal when
    /// a login exists. With the gate on, nothing is taken in: the refresh
    /// path checks the login before showing it.
    func freshIdentityDigest() async -> String? {
        guard !isRetired else { return nil }
        let started = generation
        if await reconcileTokenIfChanged() {
            // The numbers on screen are the previous login's.
            Task { [weak self] in await self?.refresh(force: true) }
        }
        guard let token = await readToken(), generation == started else { return nil }
        guard let profile = try? await repository.fetchProfile(token: token, proxyConfig: proxyConfig),
              generation == started else { return nil }
        guard identityGate == nil else { return Self.identityDigest(of: profile) }
        return applyProfile(profile)
    }

    /// Whether this store's scope holds any login at all. Attributes only for
    /// the Keychain, like onboarding's detection.
    func hasTokenSource() -> Bool {
        tokenProvider.hasTokenSource()
    }

    /// The same question off the main thread.
    func detectTokenSource() async -> Bool {
        let provider = tokenProvider
        return await Task.detached(priority: .userInitiated) { provider.hasTokenSource() }.value
    }

    /// Points the store at another config folder (#294). Everything shown
    /// came from the previous login, so it is dropped rather than left on
    /// screen under the new folder: from memory, from the shared file the
    /// widgets and the next `loadCached()` read, and from whatever refresh
    /// was still out. The next refresh fills it again.
    func reconfigure(scope: CredentialScope) {
        abandonInFlightWork()
        tokenProvider.reconfigure(scope: scope)
        sharedFileService.clearUsage()
        sharedFileService.invalidateCache()
        resetDisplayedUsage()
        errorState = .none
        authFailureHint = nil
        lastAPIError = nil
        hasConfig = false
        retryAfterDate = nil
        consecutiveRateLimits = 0
        currentSpeed = .normal
        fastModeStart = nil
        lastProfileFetch = nil
        verifiedToken = nil
        if identityState != .unchecked { identityState = .unchecked }
        reloadWidgets()
    }

    /// Every number, date and plan fact back to its empty state, pacing
    /// samples included.
    private func resetDisplayedUsage() {
        lastUsage = nil
        lastUpdate = nil
        fiveHourPct = 0
        sevenDayPct = 0
        sonnetPct = 0
        opusPct = 0
        coworkPct = 0
        fablePct = 0
        oauthAppsPct = 0
        hasOpus = false
        hasCowork = false
        hasFable = false
        hasSonnet = false
        extraUsage = nil
        planType = .unknown
        rateLimitTier = nil
        organizationName = nil
        maskedEmail = nil
        lastIdentityDigest = nil
        fiveHourReset = ""
        fiveHourResetAbsolute = ""
        sevenDayReset = ""
        sevenDayResetAbsolute = ""
        fableReset = ""
        fableResetAbsolute = ""
        sonnetReset = ""
        sonnetResetAbsolute = ""
        applyPacing([:])
        sessionSamples = []
        UserDefaults.standard.removeObject(forKey: sessionSamplesKey)
    }

    /// Applies a successful usage fetch: updates the published UI state, clears
    /// every error/backoff field, resets the adaptive speed, and fires the
    /// notification + widget side effects. Shared by the nominal path and the
    /// post-401 retry so the two can never drift.
    private func applySuccess(usage: UsageResponse) {
        repository.saveUsage(usage, fetchedAt: Date())
        updateUI(from: usage)
        appendSessionSample(from: usage)
        errorState = .none
        lastAPIError = nil
        authFailureHint = nil
        lastUpdate = Date()
        if currentSpeed == .slow {
            currentSpeed = .normal
        }
        retryAfterDate = nil
        consecutiveRateLimits = 0
        notificationService.endTokenAlertEpisode()
        reloadWidgets()
        evaluateNotifications(usage: usage)
    }

    // MARK: - Private

    func updateUI(from usage: UsageResponse) {
        lastUsage = usage
        fiveHourPct = Int(usage.fiveHour?.utilization ?? 0)
        sevenDayPct = Int(usage.sevenDay?.utilization ?? 0)
        sonnetPct = Int(usage.sevenDaySonnet?.utilization ?? 0)
        opusPct = Int(usage.sevenDayOpus?.utilization ?? 0)
        coworkPct = Int(usage.sevenDayCowork?.utilization ?? 0)
        fablePct = Int(usage.sevenDayFable?.utilization ?? 0)
        oauthAppsPct = Int(usage.sevenDayOauthApps?.utilization ?? 0)
        hasOpus = usage.sevenDayOpus != nil
        hasCowork = usage.sevenDayCowork != nil
        hasFable = usage.sevenDayFable != nil
        hasSonnet = usage.sevenDaySonnet != nil
        extraUsage = usage.extraUsage

        refreshResetCountdown()

        applyPacing(PacingCalculator.calculateAll(from: usage, margin: Double(pacingMargin), activeDays: pacingSchedule.effectiveActiveDays, activeHours: pacingSchedule.effectiveHours))
    }

    func refreshResetCountdown() {
        let session = ResetCountdownFormatter.session(from: lastUsage?.fiveHour?.resetsAtDate)
        fiveHourReset = session.relative
        fiveHourResetAbsolute = session.absolute
        let weekly = ResetCountdownFormatter.weekly(from: lastUsage?.sevenDay?.resetsAtDate)
        sevenDayReset = weekly.relative
        sevenDayResetAbsolute = weekly.absolute
        // Fable is a weekly bucket with its own reset timestamp.
        let fable = ResetCountdownFormatter.weekly(from: lastUsage?.sevenDayFable?.resetsAtDate)
        fableReset = fable.relative
        fableResetAbsolute = fable.absolute
        // Sonnet also uses the 7d cadence - it's a separate Sonnet-specific pool
        // on top of the global weekly limit.
        let sonnet = ResetCountdownFormatter.weekly(from: lastUsage?.sevenDaySonnet?.resetsAtDate)
        sonnetReset = sonnet.relative
        sonnetResetAbsolute = sonnet.absolute
    }

    func recalculatePacing() {
        guard let usage = lastUsage else { return }
        applyPacing(PacingCalculator.calculateAll(from: usage, margin: Double(pacingMargin), activeDays: pacingSchedule.effectiveActiveDays, activeHours: pacingSchedule.effectiveHours))
    }

    /// Builds metric snapshots + pacing zones from the latest API response and
    /// hands them to `NotificationService.evaluate` along with the current
    /// toggles. Skipped when no toggles provider is wired (e.g. tests).
    private func evaluateNotifications(usage: UsageResponse) {
        guard let toggles = notifTogglesProvider?() else { return }

        let fiveHourSnap = MetricSnapshot(
            pct: fiveHourPct,
            resetsAt: usage.fiveHour?.resetsAtDate,
            windowDuration: 5 * 3600,
            utilization: usage.fiveHour?.utilization ?? Double(fiveHourPct)
        )
        let sevenDaySnap = MetricSnapshot(
            pct: sevenDayPct,
            resetsAt: usage.sevenDay?.resetsAtDate,
            windowDuration: 7 * 86_400,
            utilization: usage.sevenDay?.utilization ?? Double(sevenDayPct)
        )
        // Nil when the response carries no Sonnet limit, so no alert can
        // fire for a quota this account does not have.
        let sonnetSnap = usage.sevenDaySonnet.map { bucket in
            MetricSnapshot(
                pct: sonnetPct,
                resetsAt: bucket.resetsAtDate,
                windowDuration: 7 * 86_400,
                utilization: bucket.utilization
            )
        }
        let fableSnap = MetricSnapshot(
            pct: fablePct,
            resetsAt: usage.sevenDayFable?.resetsAtDate,
            windowDuration: 7 * 86_400,
            utilization: usage.sevenDayFable?.utilization ?? Double(fablePct)
        )

        notificationService.evaluate(
            fiveHour: fiveHourSnap,
            sevenDay: sevenDaySnap,
            sonnet: sonnetSnap,
            fable: fableSnap,
            sessionPacing: fiveHourPacing?.zone,
            weeklyPacing: pacingZone,
            extraUsage: extraUsage,
            toggles: toggles
        )

        notificationService.scheduleResetReminders(
            sessionResetsAt: usage.fiveHour?.resetsAtDate,
            weeklyResetsAt: usage.sevenDay?.resetsAtDate,
            toggles: toggles
        )
    }

    private func applyPacing(_ allPacing: [PacingBucket: PacingResult]) {
        if let pacing = allPacing[.sevenDay] {
            pacingDelta = Int(pacing.delta)
            pacingZone = pacing.zone
            pacingResult = pacing
        } else {
            pacingDelta = 0
            pacingZone = .onTrack
            pacingResult = nil
        }
        fiveHourPacing = allPacing[.fiveHour]
        sonnetPacing = allPacing[.sonnet]
        fablePacing = allPacing[.fable]
    }
}

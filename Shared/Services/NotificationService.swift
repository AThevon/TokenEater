import Foundation
import UserNotifications

// MARK: - Usage Level

enum UsageLevel: Int, Comparable {
    case green = 0
    case orange = 1
    case red = 2

    static func < (lhs: UsageLevel, rhs: UsageLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Threshold-only level. Used as fallback and when smart color is disabled.
    static func from(pct: Int, thresholds: UsageThresholds = .default) -> UsageLevel {
        if pct >= thresholds.criticalPercent { return .red }
        if pct >= thresholds.warningPercent { return .orange }
        return .green
    }

    /// Mirrors `ThemeColors.smartLevel` so notifications align with the gauge
    /// color the user actually sees. Couples threshold severity with pacing
    /// severity, applies the reset-imminent override, and falls back to the
    /// pure threshold path when no resetDate / windowDuration is available.
    static func from(
        smartUtilization utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds = .default,
        pacingMargin: Double = 10,
        now: Date = Date(),
        profile: SmartColorProfile = .default
    ) -> UsageLevel {
        // Reuse the same decision tree as the gauge so the user-visible
        // signals stay in sync. We use the default theme since the threshold
        // logic only depends on `thresholds`, not on the colour palette.
        let level = ThemeColors.default.smartLevel(
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now,
            profile: profile
        )
        switch level {
        case .critical: return .red
        case .warning:  return .orange
        case .normal:   return .green
        }
    }
}

// MARK: - Notification Delegate

/// Allows notifications to display as banners even when the app is in the foreground.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Surface

/// Identifier for each metric the service tracks. Drives copy lookup, the
/// last-level UserDefaults key, and the toggle gate.
private enum Surface: String {
    case fiveHour
    case weekly
    case sonnet
    case fable
    case codexSession
    case codexWeekly

    /// Which provider the alert is about. It goes in the banner subtitle and
    /// in the thread identifier, so macOS groups each provider's alerts
    /// together and every banner says who it is about.
    var provider: MetricProvider {
        switch self {
        case .codexSession, .codexWeekly: return .codex
        case .fiveHour, .weekly, .sonnet, .fable: return .claude
        }
    }

    /// Which copy family the alert reads.
    ///
    /// Deliberately shared between providers: a session window is a session
    /// window whoever serves it, and the provider is named in the subtitle
    /// rather than baked into every title. The Codex family used to duplicate
    /// all of this with a "Codex " prefix, which meant Claude's alerts were
    /// the anonymous ones and a third provider would have cost twenty more
    /// strings to translate.
    var bodyFamily: String {
        switch self {
        case .fiveHour, .codexSession: return "fivehour"
        case .weekly, .codexWeekly: return "weekly"
        case .sonnet: return "sonnet"
        case .fable: return "fable"
        }
    }

    /// Copy family for the "your quota is back" alert. Provider-neutral on
    /// purpose: only OpenAI fires it today, and Claude gaining the same
    /// detector must not mean writing the strings again.
    var resetFamily: String {
        usesCountdownBody ? "session" : "weekly"
    }

    /// Windows shorter than a day render a countdown ("2h 15min left"); longer
    /// ones render a weekday and time.
    var usesCountdownBody: Bool {
        self == .fiveHour || self == .codexSession
    }

    init?(codexKind: CodexWindowKind) {
        switch codexKind {
        case .session: self = .codexSession
        case .weekly: self = .codexWeekly
        // An unfamiliar window has no copy written for it, so it is tracked on
        // the dashboard but never notified about.
        case .other: return nil
        }
    }
}

// MARK: - Notification Service

final class NotificationService: NotificationServiceProtocol {
    private let center: NotificationCenterProtocol
    private let state: NotificationStateStore

    init(
        center: NotificationCenterProtocol = LiveNotificationCenter(),
        stateStore: NotificationStateStore = UserDefaultsNotificationStateStore()
    ) {
        self.center = center
        self.state = stateStore
    }

    func setupDelegate() {
        center.setDelegate(NotificationDelegate.shared)
    }

    func requestPermission() {
        setupDelegate()
        center.requestAuthorization()
    }

    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.authorizationStatus()
    }

    func sendTest(for provider: MetricProvider?) {
        let content = content(for: provider)
        content.title = String(localized: "notif.title.test")
        content.body = String(localized: "notif.body.test")
        send(id: "test_\(Date().timeIntervalSince1970)", content: content)
    }

    /// Every notification the app sends is built here, so none can ship
    /// without saying who it is about. The subtitle is the line macOS renders
    /// under the title; the thread identifier is what makes Notification
    /// Center stack a provider's alerts together instead of interleaving two
    /// providers' windows in one undifferentiated pile.
    private func content(for provider: MetricProvider?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.sound = .default
        if let provider {
            content.subtitle = provider.displayName
            content.threadIdentifier = provider.rawValue
        }
        return content
    }

    // MARK: - Main evaluation

    func evaluate(
        fiveHour: MetricSnapshot,
        sevenDay: MetricSnapshot,
        sonnet: MetricSnapshot,
        fable: MetricSnapshot,
        sessionPacing: PacingZone?,
        weeklyPacing: PacingZone?,
        extraUsage: ExtraUsage?,
        toggles: NotificationToggles
    ) {
        // Master switch. When the user flipped notifications off in Settings,
        // we skip every per-event check (and also drop any pending scheduled
        // reminders so a switch-back doesn't fire stale ones).
        guard toggles.masterEnabled, toggles.claudeEnabled else {
            center.removePending(identifiers: ["reminder_session", "reminder_weekly"])
            return
        }

        // Threshold / smart-aware notifications, one surface at a time.
        if toggles.trackFiveHour {
            checkSurface(.fiveHour, snapshot: fiveHour, pacing: sessionPacing, toggles: toggles)
        }
        if toggles.trackWeekly {
            checkSurface(.weekly, snapshot: sevenDay, pacing: weeklyPacing, toggles: toggles)
        }
        if toggles.trackSonnet {
            checkSurface(.sonnet, snapshot: sonnet, pacing: weeklyPacing, toggles: toggles)
        }
        if toggles.trackFable {
            checkSurface(.fable, snapshot: fable, pacing: weeklyPacing, toggles: toggles)
        }

        // Pacing zone transitions, gated independently from threshold alerts.
        if let zone = sessionPacing {
            checkPacingTransition(zone, surface: .fiveHour, toggles: toggles)
        }
        if let zone = weeklyPacing {
            checkPacingTransition(zone, surface: .weekly, toggles: toggles)
        }

        // Extra credits pool.
        if toggles.extraCredits, let extra = extraUsage, extra.isEnabled {
            checkExtraCredits(extra, toggles: toggles)
        }
    }

    // MARK: - Surface check

    /// - Parameter allowsRecovery: false for surfaces whose "you are back"
    ///   signal is delivered by a dedicated alert instead. Codex windows use the
    ///   explicit window-reset notification, so letting this fire too would
    ///   announce the same rollover twice.
    private func checkSurface(
        _ surface: Surface,
        snapshot: MetricSnapshot,
        pacing: PacingZone?,
        toggles: NotificationToggles,
        allowsRecovery: Bool = true
    ) {
        let key = "lastLevel_\(surface.rawValue)"
        let previousRaw = state.lastLevel(forKey: key)
        let previous = UsageLevel(rawValue: previousRaw) ?? .green
        let absoluteLevel: UsageLevel = .from(pct: snapshot.pct, thresholds: toggles.thresholds)
        let current: UsageLevel = toggles.smartColorEnabled
            ? .from(smartUtilization: snapshot.utilization,
                    resetDate: snapshot.resetsAt,
                    windowDuration: snapshot.windowDuration,
                    thresholds: toggles.thresholds,
                    pacingMargin: toggles.pacingMargin,
                    profile: toggles.smartColorProfile)
            : absoluteLevel

        // Track the window reset boundary. A real reset moves `resets_at`
        // meaningfully forward (the window rolled); a mid-window refresh keeps
        // it stable. The recovery ("new cycle") alert is gated on this so it
        // no longer fires just because Smart Color eased the level back to
        // green mid-window (#244) - which produced a false "weekly reset"
        // notification on a random weekday. The baseline updates every call,
        // independent of the level-change guard below.
        let resetKey = "lastResetsAt_\(surface.rawValue)"
        let previousReset = state.lastResetsAt(forKey: resetKey)
        let windowDidReset: Bool = {
            guard let now = snapshot.resetsAt, let previousReset else { return false }
            return now.timeIntervalSince(previousReset) > 3600
        }()
        if let resetsAt = snapshot.resetsAt {
            state.setLastResetsAt(resetsAt, forKey: resetKey)
        }

        // First observation of this surface: record where it stands and stay
        // quiet. A notification reports a transition, and there is nothing to
        // transition from yet. Without this an absent baseline reads as green,
        // so a provider enabled while already past a threshold announces itself
        // seconds later - which for an auto-detected provider is an alert the
        // user never asked for.
        guard state.hasBaseline(forKey: key) else {
            state.setLastLevel(current.rawValue, forKey: key)
            return
        }

        guard current != previous else { return }
        state.setLastLevel(current.rawValue, forKey: key)

        // When Smart Color escalates ABOVE the raw-threshold level, the alert is
        // driven by rate/projection, not by nearing the cap. The copy then says
        // "ahead of pace" instead of "almost capped", so a moderate % doesn't
        // read as a hard ceiling (see issue #187).
        let paceDriven = toggles.smartColorEnabled && current > absoluteLevel

        if current > previous {
            notifyEscalation(surface: surface, level: current, snapshot: snapshot, pacing: pacing, paceDriven: paceDriven)
        } else if current == .green && previous > .green && allowsRecovery && toggles.sendRecovery && windowDidReset {
            notifyRecovery(surface: surface, snapshot: snapshot)
        }
    }

    private func notifyEscalation(
        surface: Surface,
        level: UsageLevel,
        snapshot: MetricSnapshot,
        pacing: PacingZone?,
        paceDriven: Bool
    ) {
        let content = content(for: surface.provider)
        content.title = title(for: surface, level: level, pacing: pacing, paceDriven: paceDriven)
        content.body = body(for: surface, level: level, snapshot: snapshot, pacing: pacing, paceDriven: paceDriven)
        send(id: "escalation_\(surface.rawValue)", content: content)
    }

    private func notifyRecovery(surface: Surface, snapshot: MetricSnapshot) {
        let content = content(for: surface.provider)
        content.title = NSLocalizedString("notif.title.\(surface.bodyFamily).green", comment: "")
        content.body = recoveryBody(surface: surface, resetsAt: snapshot.resetsAt)
        send(id: "recovery_\(surface.rawValue)", content: content)
    }

    // MARK: - Pacing transitions

    private func checkPacingTransition(_ zone: PacingZone, surface: Surface, toggles: NotificationToggles) {
        let key = "lastPacing_\(surface.rawValue)"
        let previous = state.lastPacing(forKey: key) ?? PacingZone.onTrack.rawValue

        // Only fire on entry to a "loud" zone, and only if the toggle for that
        // zone is on. Recovery to chill / onTrack stays silent (the absence of
        // the alert IS the recovery signal).
        // Same first-observation rule as the level machine above: entering a
        // loud zone is a transition, and the first reading is not one.
        guard state.hasBaseline(forKey: key) else {
            state.setLastPacing(zone.rawValue, forKey: key)
            return
        }

        if zone.rawValue == previous { return }
        state.setLastPacing(zone.rawValue, forKey: key)

        switch zone {
        case .hot:
            guard toggles.pacingHot else { return }
            firePacing(zone: .hot, surface: surface)
        case .warning:
            guard toggles.pacingWarning else { return }
            firePacing(zone: .warning, surface: surface)
        case .chill, .onTrack:
            return
        }
    }

    /// The identifier carries the provider as well as the zone. It used to be
    /// the zone alone, so one provider going hot replaced the other provider's
    /// banner saying the same thing about a different account.
    private func firePacing(zone: PacingZone, surface: Surface) {
        let content = content(for: surface.provider)
        content.title = NSLocalizedString("notif.title.pacing.\(zone.rawValue)", comment: "")
        content.body = NSLocalizedString("notif.body.pacing.\(zone.rawValue)", comment: "")
        send(id: "pacing_\(surface.provider.rawValue)_\(zone.rawValue)", content: content)
    }

    // MARK: - Extra credits

    private func checkExtraCredits(_ extra: ExtraUsage, toggles: NotificationToggles) {
        let pct = Int(extra.utilization ?? 0)
        let level = UsageLevel.from(pct: pct, thresholds: toggles.thresholds)
        let key = "lastLevel_extra"
        let previousRaw = state.lastLevel(forKey: key)
        let previous = UsageLevel(rawValue: previousRaw) ?? .green
        guard level != previous else { return }
        state.setLastLevel(level.rawValue, forKey: key)

        switch level {
        case .orange, .red:
            let content = content(for: .claude)
            let extraKey = level == .red ? "red" : "orange"
            content.title = NSLocalizedString("notif.title.extra.\(extraKey)", comment: "")
            content.body = String(format: NSLocalizedString("notif.body.extra.\(extraKey)", comment: ""), pct)
            send(id: "escalation_extra", content: content)
        case .green where previous > .green && toggles.sendRecovery:
            let content = content(for: .claude)
            content.title = String(localized: "notif.title.extra.green")
            content.body = String(localized: "notif.body.extra.green")
            send(id: "recovery_extra", content: content)
        default:
            return
        }
    }

    // MARK: - Codex

    private static let codexReminderIdentifiers = ["reminder_codex_session", "reminder_codex_weekly"]

    func evaluateCodex(windows: [CodexWindowSnapshot], toggles: NotificationToggles) {
        guard toggles.masterEnabled, toggles.codex.enabled else {
            cancelCodexReminders()
            return
        }

        let session = windows.first { $0.kind == .session }
        let weekly = windows.first { $0.kind == .weekly }

        // The rollover alert runs before the level machine so a reset is
        // announced as "quota is back", not as a level dip. They keep separate
        // state keys, so the order is a readability choice, not a dependency.
        if toggles.codex.windowReset {
            for window in windows {
                checkCodexWindowReset(window)
            }
        }

        if let session, toggles.codex.trackSession {
            checkSurface(.codexSession, snapshot: session.metricSnapshot, pacing: session.pacing?.zone, toggles: toggles, allowsRecovery: false)
        }
        if let weekly, toggles.codex.trackWeekly {
            checkSurface(.codexWeekly, snapshot: weekly.metricSnapshot, pacing: weekly.pacing?.zone, toggles: toggles, allowsRecovery: false)
        }

        if let zone = session?.pacing?.zone {
            checkPacingTransition(zone, surface: .codexSession, toggles: toggles)
        }
        if let zone = weekly?.pacing?.zone {
            checkPacingTransition(zone, surface: .codexWeekly, toggles: toggles)
        }

        scheduleCodexResetReminders(session: session, weekly: weekly, toggles: toggles)
    }

    func notifyCodexTokenExpired(toggles: NotificationToggles) {
        guard toggles.masterEnabled, toggles.codex.enabled, toggles.codex.tokenExpired else { return }
        let now = Date()
        // Same de-dupe budget as the Claude token alert: at most one per hour,
        // however many refreshes fail in between.
        if let last = state.codexTokenExpiredFiredAt(), now.timeIntervalSince(last) < 3600 { return }
        state.setCodexTokenExpiredFiredAt(now)

        let content = content(for: .codex)
        content.title = String(localized: "notif.title.codex.token")
        content.body = String(localized: "notif.body.codex.token")
        send(id: "codex_token_expired", content: content)
    }

    func cancelCodexReminders() {
        center.removePending(identifiers: Self.codexReminderIdentifiers)
    }

    /// Fires once when a window genuinely rolls over. The decision itself lives
    /// in `CodexResetDetector`; this only persists the two observations it
    /// compares. Its state keys are separate from `checkSurface`'s so the two
    /// state machines cannot consume each other's baseline.
    private func checkCodexWindowReset(_ window: CodexWindowSnapshot) {
        guard let surface = Surface(codexKind: window.kind), let resetDate = window.resetDate else { return }

        let resetKey = "codexResetAt_\(surface.rawValue)"
        let utilizationKey = "codexUtilization_\(surface.rawValue)"

        let previous = state.lastResetsAt(forKey: resetKey).map {
            CodexResetDetector.Observation(usedPercent: state.lastUtilization(forKey: utilizationKey) ?? 0, resetAt: $0)
        }
        let current = CodexResetDetector.Observation(usedPercent: window.utilization, resetAt: resetDate)
        let didReset = CodexResetDetector.didReset(
            previous: previous,
            current: current,
            windowDuration: window.windowDuration
        )

        state.setLastResetsAt(resetDate, forKey: resetKey)
        state.setLastUtilization(window.utilization, forKey: utilizationKey)

        guard didReset else { return }

        let content = content(for: surface.provider)
        content.title = NSLocalizedString("notif.title.reset.\(surface.resetFamily)", comment: "")
        let bodyKey = "notif.body.reset.\(surface.resetFamily)"
        if surface.usesCountdownBody {
            content.body = String(format: NSLocalizedString(bodyKey, comment: ""), NotificationBodyFormatter.formatTime(resetDate))
        } else {
            content.body = String(format: NSLocalizedString(bodyKey, comment: ""), NotificationBodyFormatter.formatDateTime(resetDate))
        }
        send(id: "codex_reset_\(surface.rawValue)", content: content)
    }

    /// Reminders reuse the Claude offsets so one setting drives both providers.
    /// Idle windows are skipped: their deadline is recomputed as `now + window`
    /// on every poll, so a reminder against it would be rescheduled forever and
    /// never describe a real deadline.
    private func scheduleCodexResetReminders(
        session: CodexWindowSnapshot?,
        weekly: CodexWindowSnapshot?,
        toggles: NotificationToggles
    ) {
        cancelCodexReminders()

        if toggles.codex.resetReminderSession, let session, !session.isIdle,
           let target = session.resetDate?.addingTimeInterval(-Double(toggles.resetReminderSessionOffsetMinutes) * 60),
           target.timeIntervalSinceNow > 0 {
            let duration = formatReminderDuration(minutes: toggles.resetReminderSessionOffsetMinutes)
            schedule(
                id: "reminder_codex_session",
                title: String(format: NSLocalizedString("notif.title.reminder.session", comment: ""), duration),
                body: NSLocalizedString("notif.body.reminder.session", comment: ""),
                fireDate: target,
                provider: .codex
            )
        }

        if toggles.codex.resetReminderWeekly, let weekly, !weekly.isIdle,
           let target = weekly.resetDate?.addingTimeInterval(-Double(toggles.resetReminderWeeklyOffsetMinutes) * 60),
           target.timeIntervalSinceNow > 0 {
            let duration = formatReminderDuration(minutes: toggles.resetReminderWeeklyOffsetMinutes)
            schedule(
                id: "reminder_codex_weekly",
                title: String(format: NSLocalizedString("notif.title.reminder.weekly", comment: ""), duration),
                body: NSLocalizedString("notif.body.reminder.weekly", comment: ""),
                fireDate: target,
                provider: .codex
            )
        }
    }

    // MARK: - Vendor health (outage / restored)

    /// Edge-triggered, exactly mirroring `checkSurface`'s dedup model: persist
    /// the last health under a UserDefaults key, bail when unchanged, then fire
    /// once on healthy->degraded/down and once on ->healthy. Planned maintenance
    /// is shown in the UI but never notified, and is NOT persisted, so it can't
    /// produce a phantom "restored" alert when the window ends.
    func checkVendorHealth(_ status: VendorStatus, toggles: NotificationToggles) {
        // `Vendor` only knows Claude today, and an outage alert is about that
        // provider, so it follows that provider's master.
        guard toggles.masterEnabled, toggles.claudeEnabled else { return }
        let key = "lastVendorHealth_\(status.vendor.rawValue)"
        let previous = VendorHealth(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .healthy
        let current = status.health
        guard current != previous else { return }

        // Planned maintenance: don't advance state, don't notify.
        if current != .healthy, status.isMaintenanceOnly { return }

        UserDefaults.standard.set(current.rawValue, forKey: key)

        if current == .healthy {
            guard toggles.vendorRestored else { return }
            let content = content(for: .claude)
            content.title = NSLocalizedString("notif.title.status.\(status.vendor.rawValue).restored", comment: "")
            content.body = NSLocalizedString("notif.body.status.\(status.vendor.rawValue).restored", comment: "")
            send(id: "vendor_restored_\(status.vendor.rawValue)", content: content)
        } else {
            guard toggles.vendorDegraded else { return }
            let levelKey = current == .down ? "down" : "degraded"
            let content = content(for: .claude)
            content.title = NSLocalizedString("notif.title.status.\(status.vendor.rawValue).\(levelKey)", comment: "")
            // Prefer the live incident headline; fall back to generic copy.
            if let incident = status.activeIncidents.first {
                content.body = incident.name
            } else {
                content.body = NSLocalizedString("notif.body.status.\(status.vendor.rawValue).\(levelKey)", comment: "")
            }
            send(id: "vendor_outage_\(status.vendor.rawValue)", content: content)
        }
    }

    // MARK: - Token expired

    func notifyTokenExpired(toggles: NotificationToggles) {
        guard toggles.masterEnabled, toggles.claudeEnabled, toggles.tokenExpired else { return }
        let now = Date()
        // De-dupe: only one token-expired notif per hour.
        if let last = state.tokenExpiredFiredAt(),
           now.timeIntervalSince(last) < 3600 {
            return
        }
        state.setTokenExpiredFiredAt(now)

        let content = content(for: .claude)
        content.title = String(localized: "notif.title.token")
        content.body = String(localized: "notif.body.token")
        send(id: "token_expired", content: content)
    }

    // MARK: - Reset reminders (scheduled)

    func scheduleResetReminders(
        sessionResetsAt: Date?,
        weeklyResetsAt: Date?,
        toggles: NotificationToggles
    ) {
        // Cancel previous schedules so a moving target doesn't pile up. Also
        // the way a muted provider loses its pending reminders.
        center.removePending(identifiers: ["reminder_session", "reminder_weekly"])
        guard toggles.masterEnabled, toggles.claudeEnabled else { return }

        if toggles.resetReminderSession,
           let target = sessionResetsAt?.addingTimeInterval(-Double(toggles.resetReminderSessionOffsetMinutes) * 60),
           target.timeIntervalSinceNow > 0 {
            let duration = formatReminderDuration(minutes: toggles.resetReminderSessionOffsetMinutes)
            let titleTemplate = NSLocalizedString("notif.title.reminder.session", comment: "")
            schedule(
                id: "reminder_session",
                title: String(format: titleTemplate, duration),
                body: NSLocalizedString("notif.body.reminder.session", comment: ""),
                fireDate: target,
                provider: .claude
            )
        }
        if toggles.resetReminderWeekly,
           let target = weeklyResetsAt?.addingTimeInterval(-Double(toggles.resetReminderWeeklyOffsetMinutes) * 60),
           target.timeIntervalSinceNow > 0 {
            let duration = formatReminderDuration(minutes: toggles.resetReminderWeeklyOffsetMinutes)
            let titleTemplate = NSLocalizedString("notif.title.reminder.weekly", comment: "")
            schedule(
                id: "reminder_weekly",
                title: String(format: titleTemplate, duration),
                body: NSLocalizedString("notif.body.reminder.weekly", comment: ""),
                fireDate: target,
                provider: .claude
            )
        }
    }

    /// Renders a human-readable duration matching the picker labels in the
    /// settings UI: "1 h", "2 h" for round-hour values, "5 min", "30 min" for
    /// minute-resolution offsets.
    private func formatReminderDuration(minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return String(format: NSLocalizedString("notif.duration.hours", comment: ""), hours)
        }
        return String(format: NSLocalizedString("notif.duration.minutes", comment: ""), minutes)
    }

    private func schedule(id: String, title: String, body: String, fireDate: Date, provider: MetricProvider) {
        let content = content(for: provider)
        content.title = title
        content.body = body

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Title / body lookups

    private func title(for surface: Surface, level: UsageLevel, pacing: PacingZone?, paceDriven: Bool) -> String {
        // Runtime-composed keys must go through `NSLocalizedString` to actually
        // hit the .strings file. `String(localized: String.LocalizationValue(_))`
        // takes a runtime String as a default value rather than as a key, so it
        // happily returns the literal "notif.title.fivehour.green" if used here.
        // PacingZone.onTrack has rawValue "onTrack" (camelCase) but the strings
        // use lowercase to keep keys stylistically aligned, so we normalise.

        // 7-day buckets escalated by pace (not raw usage): rate-oriented title
        // instead of the absolute "almost capped" wording.
        if paceDriven, level != .green, !surface.usesCountdownBody {
            return NSLocalizedString("notif.title.\(surface.bodyFamily).pace", comment: "")
        }
        // Session windows get the pacing-qualified title on both providers:
        // the nuance was written for the 5-hour window, and OpenAI's session
        // window is the same kind of window with the same pacing data.
        if surface.usesCountdownBody, level == .orange, let pacing {
            return NSLocalizedString("notif.title.\(surface.bodyFamily).orange.\(pacing.rawValue.lowercased())", comment: "")
        }
        let levelKey = level == .red ? "red" : (level == .orange ? "orange" : "green")
        return NSLocalizedString("notif.title.\(surface.bodyFamily).\(levelKey)", comment: "")
    }

    private func body(for surface: Surface, level: UsageLevel, snapshot: MetricSnapshot, pacing: PacingZone?, paceDriven: Bool) -> String {
        // Pace-driven escalation on a 7-day bucket: a rate-oriented body that
        // doesn't imply a hard ceiling. No date arg (format ignores extras).
        // Must match the guard in `title(for:)` exactly. It was updated to
        // `usesCountdownBody` and this one was left on `!= .fiveHour`, so a
        // pace-driven `.codexSession` escalation took the pace branch here
        // while the title took the normal one, and looked up
        // `notif.body.codex.session.pace`, a key that exists in neither
        // language. NSLocalizedString then returns the key, so the
        // notification body read as the key itself.
        if paceDriven, level != .green, !surface.usesCountdownBody {
            return NSLocalizedString("notif.body.\(surface.bodyFamily).pace", comment: "")
        }
        let resetsAt = snapshot.resetsAt
        switch surface {
        case .fiveHour, .codexSession:
            if let resetsAt, resetsAt.timeIntervalSinceNow > 0 {
                let countdown = NotificationBodyFormatter.formatCountdown(from: Date(), to: resetsAt)
                let pacingKey = (level == .orange) ? (pacing?.rawValue.lowercased() ?? "ontrack") : "red"
                let key = level == .red
                    ? "notif.body.\(surface.bodyFamily).red"
                    : "notif.body.\(surface.bodyFamily).orange.\(pacingKey)"
                return String(format: NSLocalizedString(key, comment: ""), countdown)
            }
            return level == .red
                ? NSLocalizedString("notif.body.\(surface.bodyFamily).red.fallback", comment: "")
                : NSLocalizedString("notif.body.\(surface.bodyFamily).orange.fallback", comment: "")
        case .weekly, .sonnet, .fable, .codexWeekly:
            if let resetsAt, resetsAt.timeIntervalSinceNow > 0 {
                let dateTime = NotificationBodyFormatter.formatDateTime(resetsAt)
                let key = level == .red
                    ? "notif.body.\(surface.bodyFamily).red"
                    : "notif.body.\(surface.bodyFamily).orange"
                return String(format: NSLocalizedString(key, comment: ""), dateTime)
            }
            return level == .red
                ? NSLocalizedString("notif.body.\(surface.bodyFamily).red.fallback", comment: "")
                : NSLocalizedString("notif.body.\(surface.bodyFamily).orange.fallback", comment: "")
        }
    }

    private func recoveryBody(surface: Surface, resetsAt: Date?) -> String {
        guard let resetsAt, resetsAt.timeIntervalSinceNow > 0 else {
            return NSLocalizedString("notif.body.\(surface.bodyFamily).green.fallback", comment: "")
        }
        switch surface {
        case .fiveHour, .codexSession:
            let time = NotificationBodyFormatter.formatTime(resetsAt)
            return String(format: NSLocalizedString("notif.body.\(surface.bodyFamily).green", comment: ""), time)
        case .weekly, .sonnet, .fable, .codexWeekly:
            let dateTime = NotificationBodyFormatter.formatDateTime(resetsAt)
            return String(format: NSLocalizedString("notif.body.\(surface.bodyFamily).green", comment: ""), dateTime)
        }
    }

    // MARK: - Send

    private func send(id: String, content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }
}

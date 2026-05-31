import SwiftUI

// MARK: - Shared color helpers
//
// The popover layouts need the same gauge/pacing colours everywhere, so we
// centralise the lookups here instead of duplicating them in every layout.

@MainActor
enum PopoverColors {
    static func gauge(pct: Int, resetDate: Date?, windowDuration: TimeInterval, theme: ThemeStore, settings: SettingsStore) -> Color {
        if settings.smartColorEnabled {
            return theme.current.smartGaugeColor(
                utilization: Double(pct),
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: theme.thresholds,
                pacingMargin: Double(settings.pacingMargin),
                profile: settings.smartColorProfile
            )
        }
        return theme.current.gaugeColor(for: Double(pct), thresholds: theme.thresholds)
    }

    static func gaugeGradient(pct: Int, resetDate: Date?, windowDuration: TimeInterval, theme: ThemeStore, settings: SettingsStore) -> LinearGradient {
        if settings.smartColorEnabled {
            return theme.current.smartGaugeGradient(
                utilization: Double(pct),
                resetDate: resetDate,
                windowDuration: windowDuration,
                thresholds: theme.thresholds,
                pacingMargin: Double(settings.pacingMargin),
                startPoint: .leading,
                endPoint: .trailing,
                profile: settings.smartColorProfile
            )
        }
        return theme.current.gaugeGradient(
            for: Double(pct),
            thresholds: theme.thresholds,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static func zone(_ zone: PacingZone, theme: ThemeStore) -> Color {
        theme.current.pacingColor(for: zone)
    }

    static func zoneGradient(_ zone: PacingZone, theme: ThemeStore) -> LinearGradient {
        theme.current.pacingGradient(for: zone, startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - PRO badge + loading indicator

struct PopoverHeader: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refreshHovering: Bool = false

    private var showBadge: Bool {
        settingsStore.popoverConfig.showPlanBadge && usageStore.planType != .unknown
    }

    private var showButton: Bool {
        settingsStore.popoverConfig.showRefreshButton
    }

    /// Top breathing room when both header items are hidden.
    /// Tuned per variant - each layout has different visual density above
    /// the hero zone, so a flat value would feel cramped on Classic and
    /// excessive on Focus.
    private var emptyHeaderHeight: CGFloat {
        switch settingsStore.popoverConfig.activeVariant {
        case .classic: return 16
        case .compact: return 12
        case .focus: return 6
        }
    }

    /// Bottom padding under the header when at least one item is shown.
    /// Focus has a tighter hero zone - 14 leaves an awkward gap there.
    private var headerBottomPadding: CGFloat {
        switch settingsStore.popoverConfig.activeVariant {
        case .classic, .compact: return 14
        case .focus: return 4
        }
    }

    var body: some View {
        if !showBadge && !showButton {
            Color.clear.frame(height: emptyHeaderHeight)
        } else {
            HStack(spacing: 0) {
                if showBadge {
                    Text(usageStore.planType.displayLabel)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(usageStore.planType.badgeColor.opacity(0.3))
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
                if showButton {
                    refreshButton
                }
            }
            .frame(height: 22)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, headerBottomPadding)
        }
    }

    @ViewBuilder private var refreshButton: some View {
        Button {
            Task { await usageStore.refresh(force: true) }
        } label: {
            Group {
                if usageStore.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(refreshHovering ? Color.blue : .white.opacity(0.55))
                }
            }
            .frame(width: 22, height: 22)
            .background(
                Circle()
                    .fill(refreshHovering ? Color.blue.opacity(0.18) : .white.opacity(0.04))
                    .overlay(
                        Circle().stroke(
                            refreshHovering ? Color.blue.opacity(0.55) : .white.opacity(0.08),
                            lineWidth: 1
                        )
                    )
            )
            .scaleEffect(refreshHovering && !reduceMotion ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(usageStore.isLoading)
        .help(String(localized: "contextmenu.refresh"))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { refreshHovering = hovering }
        }
    }
}

// MARK: - Error banner

struct PopoverErrorBanner: View {
    @EnvironmentObject private var usageStore: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch usageStore.errorState {
            case .tokenUnavailable:
                expiredContent
            case .rateLimited:
                rateLimitedContent
            case .networkError:
                networkErrorContent
            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var expiredContent: some View {
        Label(String(localized: "error.banner.expired"), systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.red)
        Text(String(localized: "error.banner.expired.hint"))
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
        HStack(spacing: 6) {
            primaryActionButton(title: String(localized: "error.banner.reauth.button")) {
                Task { await usageStore.reauthenticate() }
            }
            CopyDiagnosticButton()
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var rateLimitedContent: some View {
        Label(String(localized: "error.banner.apiunavailable"), systemImage: "icloud.slash")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.orange)
        Text(String(localized: "error.banner.apiunavailable.hint"))
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
        if let last = usageStore.lastUpdate {
            Text(String(format: String(localized: "error.banner.lastupdate"),
                        last.formatted(.relative(presentation: .named))))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        HStack(spacing: 6) {
            primaryActionButton(
                title: String(localized: "error.banner.retry.button"),
                disabled: usageStore.isLoading
            ) {
                usageStore.handleTokenChange()
                Task { await usageStore.refresh(force: true) }
            }
            CopyDiagnosticButton()
            Button {
                if let url = URL(string: "https://github.com/anthropics/claude-code/issues/31637") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                    Text(String(localized: "error.banner.apiunavailable.learnmore"))
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var networkErrorContent: some View {
        Label(String(localized: "error.network.generic"), systemImage: "wifi.slash")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.orange)
        HStack(spacing: 6) {
            primaryActionButton(
                title: String(localized: "error.banner.retry.button"),
                disabled: usageStore.isLoading
            ) {
                Task { await usageStore.refresh(force: true) }
            }
            CopyDiagnosticButton()
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func primaryActionButton(
        title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.3))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Secondary action that copies a Markdown diagnostic report to the clipboard.
/// Appears next to the primary action in `PopoverErrorBanner` for every error
/// state, so users can paste raw debug context into GitHub issues.
struct CopyDiagnosticButton: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var copied = false

    var body: some View {
        Button {
            let report = DiagnosticReporter.makeReport(
                usageStore: usageStore,
                settingsStore: settingsStore
            )
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(report, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                    .font(.system(size: 9))
                Text(copied
                     ? String(localized: "error.banner.diagnostic.copied")
                     : String(localized: "error.banner.diagnostic.button"))
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Watchers toggle

struct PopoverWatchersToggle: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                settingsStore.overlayEnabled.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: settingsStore.overlayEnabled ? "eye.fill" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(settingsStore.overlayEnabled ? .blue : .white.opacity(0.25))
                    .frame(width: 18)
                Text(String(localized: "sidebar.agentWatchers"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Circle()
                    .fill(settingsStore.overlayEnabled ? .blue : .white.opacity(0.12))
                    .frame(width: 6, height: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(settingsStore.overlayEnabled ? .blue.opacity(0.08) : .white.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Updated timestamp

struct PopoverTimestamp: View {
    @EnvironmentObject private var usageStore: UsageStore

    @State private var lastUpdateText = ""
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        // Always render. If we never refreshed, show "never" placeholder so
        // the block is visible and testable from the editor.
        Text(displayText)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.3))
            .frame(maxWidth: .infinity)
            .onAppear { refreshText() }
            .onReceive(timer) { _ in refreshText() }
            .onChange(of: usageStore.lastUpdate) { _, _ in refreshText() }
    }

    private var displayText: String {
        let text = lastUpdateText.isEmpty
            ? String(localized: "menubar.updated.never")
            : lastUpdateText
        return String(format: String(localized: "menubar.updated"), text)
    }

    private func refreshText() {
        if let date = usageStore.lastUpdate {
            lastUpdateText = date.formatted(.relative(presentation: .named))
        }
    }
}

// MARK: - Footer buttons (Open TokenEater + Quit)

struct PopoverOpenButton: View {
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openDashboard, object: nil)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8))
                Text("Open TokenEater")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.white.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct PopoverQuitButton: View {
    var body: some View {
        Button(String(localized: "menubar.quit")) {
            NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white.opacity(0.4))
    }
}

// MARK: - Pacing row (Classic variant)

struct PopoverPacingRow: View {
    @EnvironmentObject private var themeStore: ThemeStore

    let label: String
    let pacing: PacingResult

    var body: some View {
        let sign = pacing.delta >= 0 ? "+" : ""
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))

            HStack(spacing: 10) {
                PacingBar(
                    actual: pacing.actualUsage,
                    expected: pacing.expectedUsage,
                    zone: pacing.zone,
                    gradient: PopoverColors.zoneGradient(pacing.zone, theme: themeStore),
                    compact: true
                )
                .frame(maxWidth: .infinity)

                GlowText(
                    "\(sign)\(Int(pacing.delta))%",
                    font: .system(size: 12, weight: .black, design: .rounded),
                    color: PopoverColors.zone(pacing.zone, theme: themeStore),
                    glowRadius: 2
                )
                .frame(width: 48, alignment: .trailing)
            }
        }
    }
}

// MARK: - Ring blocks (hero / satellite / equal) used by Classic

/// Big hero ring used when `displaySonnet = true`. Pure visual, no
/// pin-toggle affordance - users who want to pin a metric do it from the
/// Menu bar settings section.
struct PopoverHeroRing: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        let pct = usageStore.fiveHourPct
        let resetDate = usageStore.lastUsage?.fiveHour?.resetsAtDate
        let windowDuration: TimeInterval = 5 * 3600
        let color = PopoverColors.gauge(pct: pct, resetDate: resetDate, windowDuration: windowDuration, theme: themeStore, settings: settingsStore)
        VStack(spacing: 8) {
            ZStack {
                RingGauge(
                    percentage: pct,
                    gradient: PopoverColors.gaugeGradient(pct: pct, resetDate: resetDate, windowDuration: windowDuration, theme: themeStore, settings: settingsStore),
                    size: 100,
                    glowColor: color,
                    glowRadius: 6
                )
                VStack(spacing: 2) {
                    GlowText(
                        "\(pct)%",
                        font: .system(size: 24, weight: .black, design: .rounded),
                        color: color,
                        glowRadius: 4
                    )
                    Text(String(localized: "metric.session"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            if !usageStore.fiveHourReset.isEmpty {
                Text(String(format: String(localized: "metric.reset"), usageStore.fiveHourReset))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}

/// Small satellite ring (40px). Used for Weekly or Sonnet when
/// `displaySonnet = true`.
struct PopoverSatelliteRing: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    let label: String
    let pct: Int
    let resetDate: Date?
    let windowDuration: TimeInterval

    var body: some View {
        let color = PopoverColors.gauge(pct: pct, resetDate: resetDate, windowDuration: windowDuration, theme: themeStore, settings: settingsStore)
        VStack(spacing: 4) {
            ZStack {
                RingGauge(
                    percentage: pct,
                    gradient: PopoverColors.gaugeGradient(pct: pct, resetDate: resetDate, windowDuration: windowDuration, theme: themeStore, settings: settingsStore),
                    size: 40,
                    glowColor: color,
                    glowRadius: 3
                )
                GlowText(
                    "\(pct)%",
                    font: .system(size: 10, weight: .black, design: .rounded),
                    color: color,
                    glowRadius: 2
                )
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

/// Medium ring (70px) used in the "two equal rings" layout (Classic without
/// Sonnet). Includes an optional reset countdown below.
struct PopoverEqualRing: View {
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    let label: String
    let pct: Int
    /// Empty string = hide the row.
    let resetText: String
    let resetDate: Date?
    let windowDuration: TimeInterval

    var body: some View {
        let color = PopoverColors.gauge(pct: pct, resetDate: resetDate, windowDuration: windowDuration, theme: themeStore, settings: settingsStore)
        VStack(spacing: 8) {
            ZStack {
                RingGauge(
                    percentage: pct,
                    gradient: PopoverColors.gaugeGradient(pct: pct, resetDate: resetDate, windowDuration: windowDuration, theme: themeStore, settings: settingsStore),
                    size: 70,
                    glowColor: color,
                    glowRadius: 4
                )
                VStack(spacing: 2) {
                    GlowText(
                        "\(pct)%",
                        font: .system(size: 16, weight: .black, design: .rounded),
                        color: color,
                        glowRadius: 3
                    )
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            if !resetText.isEmpty {
                Text(String(format: String(localized: "metric.reset"), resetText))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}

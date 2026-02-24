import SwiftUI
import AppKit
import WidgetKit
import Combine

// MARK: - Metric ID

enum MetricID: String, CaseIterable {
    case fiveHour = "fiveHour"
    case sevenDay = "sevenDay"
    case sonnet = "sonnet"
    case pacing = "pacing"

    var label: String {
        switch self {
        case .fiveHour: return String(localized: "metric.session")
        case .sevenDay: return String(localized: "metric.weekly")
        case .sonnet: return String(localized: "metric.sonnet")
        case .pacing: return String(localized: "pacing.label")
        }
    }

    var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .sevenDay: return "7d"
        case .sonnet: return "S"
        case .pacing: return "P"
        }
    }
}

enum PacingDisplayMode: String {
    case dot
    case dotDelta
}

enum AppErrorState: Equatable {
    case none
    case tokenExpired
    case keychainLocked
    case networkError(String)
}

// MARK: - ViewModel

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var fiveHourPct: Int = 0
    @Published var sevenDayPct: Int = 0
    @Published var sonnetPct: Int = 0
    @Published var fiveHourReset: String = ""
    @Published var pacingDelta: Int = 0
    @Published var pacingZone: PacingZone = .onTrack
    @Published var pacingResult: PacingResult?
    @Published var lastUpdate: Date?
    @Published var isLoading = false
    @Published var errorState: AppErrorState = .none
    @Published var hasConfig = false

    var hasError: Bool { errorState != .none }
    @Published var pinnedMetrics: Set<MetricID> {
        didSet { savePinnedMetrics() }
    }

    /// Token that last received a 401/403. Prevents retrying the API with a known-dead token.
    /// Cleared when the keychain provides a different token.
    private var lastFailedToken: String?

    private var timer: Timer?
    private var displaySettingsObserver: Any?
    private var themeCancellable: AnyCancellable?

    init() {
        // Load pinned metrics from UserDefaults (default: 5h + 7d)
        if let saved = UserDefaults.standard.stringArray(forKey: "pinnedMetrics") {
            pinnedMetrics = Set(saved.compactMap { MetricID(rawValue: $0) })
        } else {
            pinnedMetrics = [.fiveHour, .sevenDay]
        }
        let onboardingDone = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if onboardingDone {
            // Silent keychain read at launch — no macOS dialog.
            // Token is usually already in SharedContainer from previous session.
            if let oauth = KeychainOAuthReader.readClaudeCodeTokenSilently() {
                SharedContainer.oauthToken = oauth.accessToken
            }
            hasConfig = SharedContainer.isConfigured
            loadCached()
            startRefreshTimer()
            UsageNotificationManager.requestPermission()
            WidgetKit.WidgetCenter.shared.reloadAllTimelines()
            Task { await refresh() }
        }

        // Observe theme changes to refresh menu bar colors in real time
        themeCancellable = ThemeManager.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        // Observe display settings changes from SettingsView
        displaySettingsObserver = NotificationCenter.default.addObserver(
            forName: .displaySettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.reloadDisplaySettings()
            }
        }
    }

    func reloadDisplaySettings() {
        if let saved = UserDefaults.standard.stringArray(forKey: "pinnedMetrics") {
            let newMetrics = Set(saved.compactMap { MetricID(rawValue: $0) })
            if newMetrics != pinnedMetrics {
                pinnedMetrics = newMetrics
            }
        }
        // Force re-render for pacingDisplayMode changes
        objectWillChange.send()
    }

    func toggleMetric(_ metric: MetricID) {
        if pinnedMetrics.contains(metric) {
            // Don't allow removing the last one
            if pinnedMetrics.count > 1 {
                pinnedMetrics.remove(metric)
            }
        } else {
            pinnedMetrics.insert(metric)
        }
    }

    private func savePinnedMetrics() {
        UserDefaults.standard.set(pinnedMetrics.map(\.rawValue), forKey: "pinnedMetrics")
    }

    func pct(for metric: MetricID) -> Int {
        switch metric {
        case .fiveHour: return fiveHourPct
        case .sevenDay: return sevenDayPct
        case .sonnet: return sonnetPct
        case .pacing: return pacingDelta
        }
    }

    var pacingDisplayMode: PacingDisplayMode {
        PacingDisplayMode(rawValue: UserDefaults.standard.string(forKey: "pacingDisplayMode") ?? "dotDelta") ?? .dotDelta
    }

    var menuBarImage: NSImage {
        guard hasConfig else {
            return renderText("--", color: .tertiaryLabelColor)
        }
        if hasError {
            return renderText("!", color: .systemRed)
        }
        return renderPinnedMetrics()
    }

    func refresh() async {
        // Silently check keychain for a fresh token when we don't have a valid one,
        // or when the current one already failed (auto-recovery from Claude Code refresh).
        if !SharedContainer.isConfigured || lastFailedToken == SharedContainer.oauthToken {
            if let oauth = KeychainOAuthReader.readClaudeCodeTokenSilently() {
                if oauth.accessToken != lastFailedToken {
                    SharedContainer.oauthToken = oauth.accessToken
                    lastFailedToken = nil
                    errorState = .none
                }
                // else: same dead token in keychain, skip API call
            }
        }

        guard SharedContainer.isConfigured,
              SharedContainer.oauthToken != lastFailedToken else {
            hasConfig = lastFailedToken != nil // had a token but it's dead
            return
        }
        hasConfig = true
        isLoading = true
        defer { isLoading = false }
        do {
            let usage = try await ClaudeAPIClient.shared.fetchUsageWithRecovery()
            update(from: usage)
            errorState = .none
            lastFailedToken = nil
            lastUpdate = Date()
            WidgetCenter.shared.reloadAllTimelines()
            UsageNotificationManager.checkThresholds(
                fiveHour: fiveHourPct,
                sevenDay: sevenDayPct,
                sonnet: sonnetPct,
                thresholds: ThemeManager.shared.thresholds
            )
        } catch let error as ClaudeAPIError {
            switch error {
            case .tokenExpired:
                lastFailedToken = SharedContainer.oauthToken
                errorState = .tokenExpired
            case .keychainLocked:
                errorState = .keychainLocked
            default:
                errorState = .networkError(error.localizedDescription)
            }
        } catch {
            errorState = .networkError(error.localizedDescription)
        }
    }

    func reloadConfig() {
        // Interactive keychain read — only called from explicit user action (Connect button)
        if let oauth = KeychainOAuthReader.readClaudeCodeToken() {
            SharedContainer.oauthToken = oauth.accessToken
            lastFailedToken = nil
            errorState = .none
        }
        hasConfig = SharedContainer.isConfigured
        loadCached()
        startRefreshTimer()
        UsageNotificationManager.requestPermission()
        WidgetKit.WidgetCenter.shared.reloadAllTimelines()
        Task { await refresh() }
    }

    // MARK: - Private

    private func loadCached() {
        if let cached = ClaudeAPIClient.shared.loadCachedUsage() {
            update(from: cached.usage)
            lastUpdate = cached.fetchDate
        }
    }

    private func update(from usage: UsageResponse) {
        fiveHourPct = Int(usage.fiveHour?.utilization ?? 0)
        sevenDayPct = Int(usage.sevenDay?.utilization ?? 0)
        sonnetPct = Int(usage.sevenDaySonnet?.utilization ?? 0)

        if let reset = usage.fiveHour?.resetsAtDate {
            let diff = reset.timeIntervalSinceNow
            if diff > 0 {
                let h = Int(diff) / 3600
                let m = (Int(diff) % 3600) / 60
                fiveHourReset = h > 0 ? "\(h)h \(m)min" : "\(m)min"
            } else {
                fiveHourReset = String(localized: "relative.now")
            }
        } else {
            fiveHourReset = ""
        }

        if let pacing = PacingCalculator.calculate(from: usage) {
            pacingDelta = Int(pacing.delta)
            pacingZone = pacing.zone
            pacingResult = pacing
        }
    }

    private func startRefreshTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    // MARK: - Menu Bar Image Rendering

    private func renderPinnedMetrics() -> NSImage {
        let height: CGFloat = 22
        let str = NSMutableAttributedString()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let sepAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        let ordered: [MetricID] = [.fiveHour, .sevenDay, .sonnet, .pacing].filter { pinnedMetrics.contains($0) }
        for (i, metric) in ordered.enumerated() {
            if i > 0 {
                str.append(NSAttributedString(string: "  ", attributes: sepAttrs))
            }
            if metric == .pacing {
                let dotColor = nsColorForZone(pacingZone)
                let dotAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: dotColor,
                ]
                str.append(NSAttributedString(string: "\u{25CF}", attributes: dotAttrs))
                if pacingDisplayMode == .dotDelta {
                    let sign = pacingDelta >= 0 ? "+" : ""
                    let deltaAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
                        .foregroundColor: dotColor,
                    ]
                    str.append(NSAttributedString(string: " \(sign)\(pacingDelta)%", attributes: deltaAttrs))
                }
            } else {
                let value = pct(for: metric)
                str.append(NSAttributedString(string: "\(metric.shortLabel) ", attributes: labelAttrs))
                str.append(NSAttributedString(string: "\(value)%", attributes: pctAttrs(value)))
            }
        }

        let size = str.size()
        let imgSize = NSSize(width: ceil(size.width) + 2, height: height)
        let img = NSImage(size: imgSize)
        img.lockFocus()
        str.draw(at: NSPoint(x: 1, y: (height - size.height) / 2))
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    private func renderText(_ text: String, color: NSColor) -> NSImage {
        let height: CGFloat = 22
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: color,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let img = NSImage(size: NSSize(width: ceil(size.width) + 2, height: height))
        img.lockFocus()
        str.draw(at: NSPoint(x: 1, y: (height - size.height) / 2))
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    private func pctAttrs(_ pct: Int) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: nsColorForPct(pct),
        ]
    }

    private func nsColorForPct(_ pct: Int) -> NSColor {
        ThemeManager.shared.menuBarNSColor(for: pct)
    }

    private func nsColorForZone(_ zone: PacingZone) -> NSColor {
        ThemeManager.shared.menuBarPacingNSColor(for: zone)
    }
}

// MARK: - Popover View

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TokenEater")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Error banner
            if viewModel.errorState != .none {
                errorBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            // Metrics
            VStack(spacing: 8) {
                metricRow(id: .fiveHour, label: String(localized: "metric.session"), pct: viewModel.fiveHourPct, reset: viewModel.fiveHourReset)
                metricRow(id: .sevenDay, label: String(localized: "metric.weekly"), pct: viewModel.sevenDayPct, reset: nil)
                metricRow(id: .sonnet, label: String(localized: "metric.sonnet"), pct: viewModel.sonnetPct, reset: nil)
            }
            .padding(.horizontal, 16)

            // Pacing section
            if let pacing = viewModel.pacingResult {
                Divider()
                    .overlay(Color.white.opacity(0.08))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                viewModel.toggleMetric(.pacing)
                            }
                        } label: {
                            Image(systemName: viewModel.pinnedMetrics.contains(.pacing) ? "pin.fill" : "pin")
                                .font(.system(size: 9))
                                .foregroundStyle(viewModel.pinnedMetrics.contains(.pacing) ? colorForZone(pacing.zone) : .white.opacity(0.2))
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.pinnedMetrics.contains(.pacing) ? Text(String(localized: "menubar.hide")) : Text(String(localized: "menubar.show")))

                        Text(String(localized: "pacing.label"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        let sign = pacing.delta >= 0 ? "+" : ""
                        Text("\(sign)\(Int(pacing.delta))%")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(colorForZone(pacing.zone))
                    }

                    // Progress bar with ideal marker
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(gradientForZone(pacing.zone))
                                .frame(width: max(0, geo.size.width * CGFloat(min(pacing.actualUsage, 100)) / 100), height: 4)

                            // Ideal marker
                            Rectangle()
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 2, height: 10)
                                .offset(x: geo.size.width * CGFloat(min(pacing.expectedUsage, 100)) / 100 - 1)
                        }
                    }
                    .frame(height: 10)

                    Text(pacing.message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(colorForZone(pacing.zone).opacity(0.8))
                }
                .padding(.horizontal, 16)
            }

            // Last update
            if let date = viewModel.lastUpdate {
                let formattedDate = date.formatted(.relative(presentation: .named))
                Text(String(format: String(localized: "menubar.updated"), formattedDate))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 10)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.top, 10)

            // Actions
            HStack(spacing: 0) {
                actionButton(icon: "arrow.clockwise", label: String(localized: "menubar.refresh")) {
                    Task { await viewModel.refresh() }
                }
                actionButton(icon: "gear", label: String(localized: "menubar.settings")) {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: {
                        ($0.identifier?.rawValue ?? "").contains("settings")
                    }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        openWindow(id: "settings")
                    }
                }
                actionButton(icon: "power", label: String(localized: "menubar.quit")) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(width: 260)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)))
    }

    // MARK: - Metric Row

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.5))
    }

    private func metricRow(id: MetricID, label: String, pct: Int, reset: String?) -> some View {
        let isPinned = viewModel.pinnedMetrics.contains(id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        viewModel.toggleMetric(id)
                    }
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 9))
                        .foregroundStyle(isPinned ? colorForPct(pct) : .white.opacity(0.2))
                        .rotationEffect(.degrees(isPinned ? 0 : 45))
                }
                .buttonStyle(.plain)
                .help(isPinned ? Text(String(localized: "menubar.hide")) : Text(String(localized: "menubar.show")))

                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let reset = reset, !reset.isEmpty {
                    Text(String(format: String(localized: "metric.reset"), reset))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.25))
                }
                Text("\(pct)%")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(colorForPct(pct))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(gradientForPct(pct))
                        .frame(width: max(0, geo.size.width * CGFloat(pct) / 100), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch viewModel.errorState {
            case .tokenExpired:
                Label(String(localized: "error.banner.expired"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                Text(String(localized: "error.banner.expired.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            case .keychainLocked:
                Label(String(localized: "error.banner.keychain"), systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(String(localized: "error.banner.keychain.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            case .networkError(let message):
                Label(message, systemImage: "wifi.slash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            case .none:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func colorForZone(_ zone: PacingZone) -> Color {
        theme.current.pacingColor(for: zone)
    }

    private func gradientForZone(_ zone: PacingZone) -> LinearGradient {
        theme.current.pacingGradient(for: zone, startPoint: .leading, endPoint: .trailing)
    }

    private func colorForPct(_ pct: Int) -> Color {
        theme.current.gaugeColor(for: Double(pct), thresholds: theme.thresholds)
    }

    private func gradientForPct(_ pct: Int) -> LinearGradient {
        theme.current.gaugeGradient(for: Double(pct), thresholds: theme.thresholds, startPoint: .leading, endPoint: .trailing)
    }
}

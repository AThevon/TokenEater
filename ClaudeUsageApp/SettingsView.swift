import SwiftUI
import WidgetKit
import UserNotifications

extension Notification.Name {
    static let displaySettingsDidChange = Notification.Name("displaySettingsDidChange")
}

struct SettingsView: View {
    var onConfigSaved: (() -> Void)?

    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false
    @State private var showGuide = false
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var importSuccess = false
    @State private var authMethodLabel = ""

    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("pacingDisplayMode") private var pacingDisplayMode = "dotDelta"

    @State private var pinnedFiveHour = true
    @State private var pinnedSevenDay = true
    @State private var pinnedSonnet = false
    @State private var pinnedPacing = false

    @State private var notifStatus: UNAuthorizationStatus = .notDetermined
    @State private var notifTestCooldown = false

    @AppStorage("proxyEnabled") private var proxyEnabled = false
    @AppStorage("proxyHost") private var proxyHost = "127.0.0.1"
    @AppStorage("proxyPort") private var proxyPort = 1080

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showResetAlert = false

    // Colors for guide sheet
    private let sheetBg = Color(hex: "#141416")
    private let sheetCard = Color.white.opacity(0.04)
    private let accent = Color(hex: "#FF9F0A")

    var body: some View {
        VStack(spacing: 0) {
            // App header
            HStack(spacing: 12) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text("TokenEater")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("settings.subtitle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("v3.2.0")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            TabView {
                connectionTab
                    .tabItem {
                        Label("settings.tab.connection", systemImage: "bolt.horizontal.fill")
                    }
                displayTab
                    .tabItem {
                        Label("settings.tab.display", systemImage: "menubar.rectangle")
                    }
                themingTab
                    .tabItem {
                        Label("settings.tab.theming", systemImage: "paintpalette.fill")
                    }
                proxyTab
                    .tabItem {
                        Label("settings.tab.proxy", systemImage: "network")
                    }
            }
        }
        .frame(width: 500, height: 480)
        .onAppear { loadConfig() }
        .sheet(isPresented: $showGuide) { guideSheet }
    }

    // MARK: - Connection Tab

    private var connectionTab: some View {
        Form {
            Section {
                HStack {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("connect.button")
                            .fontWeight(.medium)
                        Text("connect.subtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !authMethodLabel.isEmpty {
                        Text(authMethodLabel)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Button("connect.button") {
                        connectAutoDetect()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isImporting)
                }

                if let message = importMessage {
                    Label(message, systemImage: importSuccess ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(importSuccess ? .green : .orange)
                }
            }

            Section {
                HStack(spacing: 12) {
                    Button {
                        testConnection()
                    } label: {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("settings.test", systemImage: "bolt.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting)

                    Button {
                        WidgetCenter.shared.reloadAllTimelines()
                    } label: {
                        Label("settings.refresh", systemImage: "arrow.clockwise")
                    }

                    Spacer()

                    Button {
                        showGuide = true
                    } label: {
                        Label("settings.guide", systemImage: "questionmark.circle")
                    }
                }

                if let result = testResult {
                    Label(
                        result.message,
                        systemImage: result.success ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(result.success ? .green : .red)
                }
            }

            Section {
                Button("settings.onboarding.reset") {
                    hasCompletedOnboarding = false
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Display Tab

    private var displayTab: some View {
        Form {
            Section("settings.menubar.title") {
                Toggle("settings.menubar.toggle", isOn: $showMenuBar)
            }

            Section {
                Toggle("metric.session", isOn: $pinnedFiveHour)
                Toggle("metric.weekly", isOn: $pinnedSevenDay)
                Toggle("metric.sonnet", isOn: $pinnedSonnet)
                Toggle("pacing.label", isOn: $pinnedPacing)
            } header: {
                Text("settings.metrics.pinned")
            } footer: {
                Text("settings.metrics.pinned.footer")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("settings.pacing.display") {
                Picker("Mode", selection: $pacingDisplayMode) {
                    Text("settings.pacing.dot").tag("dot")
                    Text("settings.pacing.dotdelta").tag("dotDelta")
                }
                .pickerStyle(.radioGroup)
            }

            Section("settings.theme.thresholds") {
                HStack {
                    Text("settings.theme.warning")
                    Slider(value: Binding(
                        get: { Double(themeManager.warningThreshold) },
                        set: { newValue in
                            let val = Int(newValue)
                            themeManager.warningThreshold = val
                            if val >= themeManager.criticalThreshold {
                                themeManager.criticalThreshold = min(val + 5, 95)
                            }
                        }
                    ), in: 10...90, step: 5)
                    Text("\(themeManager.warningThreshold)%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("settings.theme.critical")
                    Slider(value: Binding(
                        get: { Double(themeManager.criticalThreshold) },
                        set: { newValue in
                            let val = Int(newValue)
                            themeManager.criticalThreshold = val
                            if val <= themeManager.warningThreshold {
                                themeManager.warningThreshold = max(val - 5, 10)
                            }
                        }
                    ), in: 15...95, step: 5)
                    Text("\(themeManager.criticalThreshold)%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            Section("settings.notifications.title") {
                HStack {
                    Text("settings.notifications.status")
                    Spacer()
                    switch notifStatus {
                    case .authorized:
                        Label("settings.notifications.on", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .denied:
                        Label("settings.notifications.off", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    default:
                        Label("settings.notifications.unknown", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    if notifStatus == .denied {
                        Button("settings.notifications.open") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings")!)
                        }
                    } else if notifStatus != .authorized {
                        Button("settings.notifications.enable") {
                            UsageNotificationManager.requestPermission()
                            Task {
                                try? await Task.sleep(for: .seconds(0.5))
                                notifStatus = await UsageNotificationManager.checkAuthorizationStatus()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("settings.notifications.test") {
                        if notifStatus != .authorized {
                            UsageNotificationManager.requestPermission()
                        }
                        UsageNotificationManager.sendTest()
                        notifTestCooldown = true
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            notifTestCooldown = false
                            notifStatus = await UsageNotificationManager.checkAuthorizationStatus()
                        }
                    }
                    .disabled(notifTestCooldown)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadPinnedMetrics()
            Task { notifStatus = await UsageNotificationManager.checkAuthorizationStatus() }
        }
        .onChange(of: pinnedFiveHour) { _ in savePinnedMetrics() }
        .onChange(of: pinnedSevenDay) { _ in savePinnedMetrics() }
        .onChange(of: pinnedSonnet) { _ in savePinnedMetrics() }
        .onChange(of: pinnedPacing) { _ in savePinnedMetrics() }
        .onChange(of: pacingDisplayMode) { _ in
            NotificationCenter.default.post(name: .displaySettingsDidChange, object: nil)
        }
    }

    // MARK: - Theming Tab

    private var themingTab: some View {
        Form {
            // Menu bar monochrome
            Section("settings.theme.menubar") {
                Toggle("settings.theme.monochrome", isOn: $themeManager.menuBarMonochrome)
            }

            // Preset picker
            Section("settings.theme.preset") {
                Picker("settings.theme.preset", selection: $themeManager.selectedPreset) {
                    ForEach(ThemeColors.allPresets, id: \.key) { preset in
                        Text(preset.label).tag(preset.key)
                    }
                    Text("settings.theme.custom").tag("custom")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            // Custom colors (visible only when preset == "custom")
            if themeManager.selectedPreset == "custom" {
                Section("settings.theme.colors") {
                    themeColorPicker("settings.theme.gauge.normal", hex: $themeManager.customTheme.gaugeNormal)
                    themeColorPicker("settings.theme.gauge.warning", hex: $themeManager.customTheme.gaugeWarning)
                    themeColorPicker("settings.theme.gauge.critical", hex: $themeManager.customTheme.gaugeCritical)
                    themeColorPicker("settings.theme.pacing.chill", hex: $themeManager.customTheme.pacingChill)
                    themeColorPicker("settings.theme.pacing.ontrack", hex: $themeManager.customTheme.pacingOnTrack)
                    themeColorPicker("settings.theme.pacing.hot", hex: $themeManager.customTheme.pacingHot)
                    themeColorPicker("settings.theme.widget.bg", hex: $themeManager.customTheme.widgetBackground)
                    themeColorPicker("settings.theme.widget.text", hex: $themeManager.customTheme.widgetText)
                }
            }

            // Preview gauges
            Section("settings.theme.preview") {
                HStack(spacing: 24) {
                    Spacer()
                    themePreviewGauge(
                        pct: Double(max(themeManager.warningThreshold - 15, 5)),
                        label: "settings.theme.preview.normal"
                    )
                    themePreviewGauge(
                        pct: Double(themeManager.warningThreshold + themeManager.criticalThreshold) / 2.0,
                        label: "settings.theme.preview.warning"
                    )
                    themePreviewGauge(
                        pct: Double(min(themeManager.criticalThreshold + 5, 100)),
                        label: "settings.theme.preview.critical"
                    )
                    Spacer()
                }
            }

            // Reset
            Section {
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Text("settings.theme.reset")
                }
                .alert("settings.theme.reset.confirm", isPresented: $showResetAlert) {
                    Button("settings.theme.reset.cancel", role: .cancel) { }
                    Button("settings.theme.reset.action", role: .destructive) {
                        themeManager.resetToDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: themeManager.selectedPreset) { [oldPreset = themeManager.selectedPreset] newValue in
            if newValue == "custom", let source = ThemeColors.preset(for: oldPreset) {
                themeManager.customTheme = source
            }
        }
    }

    private func themeColorPicker(_ titleKey: LocalizedStringKey, hex: Binding<String>) -> some View {
        let colorBinding = Binding<Color>(
            get: { Color(hex: hex.wrappedValue) },
            set: { newColor in
                let nsColor = NSColor(newColor).usingColorSpace(.sRGB) ?? NSColor(newColor)
                let r = Int(nsColor.redComponent * 255)
                let g = Int(nsColor.greenComponent * 255)
                let b = Int(nsColor.blueComponent * 255)
                hex.wrappedValue = String(format: "#%02X%02X%02X", r, g, b)
            }
        )
        return ColorPicker(titleKey, selection: colorBinding, supportsOpacity: false)
    }

    private func themePreviewGauge(pct: Double, label: LocalizedStringKey) -> some View {
        let theme = themeManager.current
        let thresholds = themeManager.thresholds
        let color = theme.gaugeColor(for: pct, thresholds: thresholds)
        let fraction = pct / 100.0

        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 4)
                    .frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(pct))%")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Proxy Tab

    private var proxyTab: some View {
        Form {
            Section {
                Toggle("settings.proxy.toggle", isOn: $proxyEnabled)
            } footer: {
                Text("settings.proxy.footer")
            }

            Section("settings.proxy.config") {
                LabeledContent("settings.proxy.host") {
                    TextField("127.0.0.1", text: $proxyHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("settings.proxy.port") {
                    TextField("1080", value: $proxyPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80)
                }
            }
            .disabled(!proxyEnabled)

            Section {
                Text("settings.proxy.hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: proxyEnabled) { _ in onConfigSaved?() }
        .onChange(of: proxyHost) { _ in onConfigSaved?() }
        .onChange(of: proxyPort) { _ in onConfigSaved?() }
    }

    // MARK: - Guide Sheet

    private var guideSheet: some View {
        ZStack {
            sheetBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Text("guide.title")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            showGuide = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 20)

                    // Method 1: Claude Code (only method now)
                    guideSection(
                        icon: "terminal.fill",
                        color: Color(hex: "#22C55E"),
                        title: String(localized: "guide.oauth.title"),
                        badge: String(localized: "guide.oauth.badge"),
                        steps: [
                            String(localized: "guide.oauth.step1"),
                            String(localized: "guide.oauth.step2"),
                            String(localized: "guide.oauth.step3"),
                        ]
                    )

                    // Add widget
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 14))
                            .foregroundStyle(accent)
                            .frame(width: 32, height: 32)
                            .background(accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("guide.widget")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("guide.widget.detail")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(accent.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(accent.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .padding(24)
            }
        }
        .frame(width: 460, height: 360)
    }

    private func guideSection(icon: String, color: Color, title: String, badge: String? = nil, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            VStack(spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(color.opacity(0.8))
                            .frame(width: 18, height: 18)
                            .background(color.opacity(0.1))
                            .clipShape(Circle())
                        Text(.init(step))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(sheetCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
            )
        }
        .padding(.bottom, 16)
    }

    // MARK: - Config

    private func loadConfig() {
        loadPinnedMetrics()
        if let oauth = KeychainOAuthReader.readClaudeCodeToken() {
            SharedContainer.oauthToken = oauth.accessToken
            authMethodLabel = String(localized: "connect.method.oauth")
        }
    }

    private func loadPinnedMetrics() {
        if let saved = UserDefaults.standard.stringArray(forKey: "pinnedMetrics") {
            let set = Set(saved)
            pinnedFiveHour = set.contains(MetricID.fiveHour.rawValue)
            pinnedSevenDay = set.contains(MetricID.sevenDay.rawValue)
            pinnedSonnet = set.contains(MetricID.sonnet.rawValue)
            pinnedPacing = set.contains(MetricID.pacing.rawValue)
        }
    }

    private func savePinnedMetrics() {
        var metrics: [String] = []
        if pinnedFiveHour { metrics.append(MetricID.fiveHour.rawValue) }
        if pinnedSevenDay { metrics.append(MetricID.sevenDay.rawValue) }
        if pinnedSonnet { metrics.append(MetricID.sonnet.rawValue) }
        if pinnedPacing { metrics.append(MetricID.pacing.rawValue) }
        if metrics.isEmpty { metrics.append(MetricID.fiveHour.rawValue); pinnedFiveHour = true }
        UserDefaults.standard.set(metrics, forKey: "pinnedMetrics")
        NotificationCenter.default.post(name: .displaySettingsDidChange, object: nil)
    }

    // MARK: - Actions

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            let result = await ClaudeAPIClient.shared.testConnection()
            await MainActor.run {
                testResult = result
                isTesting = false
                if result.success {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }

    private func connectAutoDetect() {
        isImporting = true
        importMessage = nil

        guard let oauth = KeychainOAuthReader.readClaudeCodeToken() else {
            isImporting = false
            importMessage = String(localized: "connect.noclaudecode")
            importSuccess = false
            return
        }

        // Sync token to SharedContainer
        SharedContainer.oauthToken = oauth.accessToken

        Task {
            let result = await ClaudeAPIClient.shared.testConnection()
            await MainActor.run {
                isImporting = false
                if result.success {
                    authMethodLabel = String(localized: "connect.method.oauth")
                    importMessage = String(localized: "connect.oauth.success")
                    importSuccess = true
                    onConfigSaved?()
                } else {
                    importMessage = result.message
                    importSuccess = false
                }
            }
        }
    }
}

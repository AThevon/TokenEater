import SwiftUI
import UserNotifications

struct SettingsView: View {
    @State private var showGuide = false

    private let sheetBg = Color(hex: "#141416")
    private let sheetCard = Color.white.opacity(0.04)
    private let accent = Color(hex: "#FF9F0A")

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeaderView()
            TabView {
                ConnectionTab(showGuide: $showGuide)
                    .tabItem {
                        Label("settings.tab.connection", systemImage: "bolt.horizontal.fill")
                    }
                DisplayTab()
                    .tabItem {
                        Label("settings.tab.display", systemImage: "menubar.rectangle")
                    }
                ThemingTab()
                    .tabItem {
                        Label("settings.tab.theming", systemImage: "paintpalette.fill")
                    }
                ProxyTab()
                    .tabItem {
                        Label("settings.tab.proxy", systemImage: "network")
                    }
            }
        }
        .frame(width: 500, height: 480)
        .sheet(isPresented: $showGuide) { guideSheet }
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
}

// MARK: - Header

private struct SettingsHeaderView: View {
    @EnvironmentObject private var updateStore: UpdateStore

    private let accent = Color(hex: "#FF9F0A")

    var body: some View {
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
            HStack(spacing: 6) {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                Text("v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if updateStore.updateAvailable {
                    Button {
                        updateStore.showUpdateModal = true
                    } label: {
                        Text("update.badge")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Connection Tab

private struct ConnectionTab: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var updateStore: UpdateStore

    @Binding var showGuide: Bool
    @State private var testResult: ConnectionTestResult?
    @State private var isTesting = false
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var importSuccess = false
    @State private var authMethodLabel = ""

    var body: some View {
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
                        WidgetReloader.scheduleReload()
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
                HStack {
                    Button("update.check") {
                        Task { await updateStore.checkForUpdate(userInitiated: true) }
                    }
                    .disabled(updateStore.isChecking)

                    if updateStore.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    if let error = updateStore.updateError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else if updateStore.updateAvailable {
                        Text("update.badge")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                Button("settings.onboarding.reset") {
                    settingsStore.hasCompletedOnboarding = false
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if settingsStore.keychainTokenExists() {
                authMethodLabel = String(localized: "connect.method.oauth")
            }
            Task { await settingsStore.refreshNotificationStatus() }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            let result = await usageStore.testConnection()
            testResult = result
            isTesting = false
            if result.success {
                WidgetReloader.scheduleReload()
            }
        }
    }

    private func connectAutoDetect() {
        isImporting = true
        importMessage = nil
        guard settingsStore.keychainTokenExists() else {
            isImporting = false
            importMessage = String(localized: "connect.noclaudecode")
            importSuccess = false
            return
        }
        Task {
            let result = await usageStore.connectAutoDetect()
            isImporting = false
            if result.success {
                authMethodLabel = String(localized: "connect.method.oauth")
                importMessage = String(localized: "connect.oauth.success")
                importSuccess = true
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.reloadConfig(thresholds: themeStore.thresholds)
                themeStore.syncToSharedFile()
            } else {
                importMessage = result.message
                importSuccess = false
            }
        }
    }
}

// MARK: - Display Tab

private struct DisplayTab: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var notifTestCooldown = false

    // Local @State bindings — stable across body re-evaluations.
    // Binding to computed properties via $store.computedProp creates
    // unstable LocationProjections that the AttributeGraph can never
    // memoize, causing an infinite re-evaluation loop in Release builds.
    @State private var showFiveHour = true
    @State private var showSevenDay = true
    @State private var showSonnet = false
    @State private var showPacing = false
    @State private var warningSlider: Double = 60
    @State private var criticalSlider: Double = 85

    var body: some View {
        Form {
            Section("settings.menubar.title") {
                Toggle("settings.menubar.toggle", isOn: $settingsStore.showMenuBar)
            }

            Section {
                Toggle("metric.session", isOn: $showFiveHour)
                Toggle("metric.weekly", isOn: $showSevenDay)
                Toggle("metric.sonnet", isOn: $showSonnet)
                Toggle("pacing.label", isOn: $showPacing)
            } header: {
                Text("settings.metrics.pinned")
            } footer: {
                Text("settings.metrics.pinned.footer")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showPacing {
                Section("settings.pacing.display") {
                    Picker("Mode", selection: $settingsStore.pacingDisplayMode) {
                        Text("settings.pacing.dot").tag(PacingDisplayMode.dot)
                        Text("settings.pacing.dotdelta").tag(PacingDisplayMode.dotDelta)
                    }
                    .pickerStyle(.radioGroup)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Section("settings.theme.thresholds") {
                HStack {
                    Text("settings.theme.warning")
                    Slider(value: $warningSlider, in: 10...90, step: 5)
                    Text("\(Int(warningSlider))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("settings.theme.critical")
                    Slider(value: $criticalSlider, in: 15...95, step: 5)
                    Text("\(Int(criticalSlider))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            Section("settings.notifications.title") {
                HStack {
                    Text("settings.notifications.status")
                    Spacer()
                    switch settingsStore.notificationStatus {
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
                    if settingsStore.notificationStatus == .denied {
                        Button("settings.notifications.open") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings")!)
                        }
                    } else if settingsStore.notificationStatus != .authorized {
                        Button("settings.notifications.enable") {
                            settingsStore.requestNotificationPermission()
                            Task {
                                try? await Task.sleep(for: .seconds(0.5))
                                await settingsStore.refreshNotificationStatus()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button("settings.notifications.test") {
                        if settingsStore.notificationStatus != .authorized {
                            settingsStore.requestNotificationPermission()
                        }
                        settingsStore.sendTestNotification()
                        notifTestCooldown = true
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            notifTestCooldown = false
                            await settingsStore.refreshNotificationStatus()
                        }
                    }
                    .disabled(notifTestCooldown)
                }
            }
        }
        .formStyle(.grouped)
        // Initialize local state from stores
        .task {
            warningSlider = Double(themeStore.warningThreshold)
            criticalSlider = Double(themeStore.criticalThreshold)
            showFiveHour = settingsStore.pinnedMetrics.contains(.fiveHour)
            showSevenDay = settingsStore.pinnedMetrics.contains(.sevenDay)
            showSonnet = settingsStore.pinnedMetrics.contains(.sonnet)
            showPacing = settingsStore.pinnedMetrics.contains(.pacing)
        }
        // Sync: local toggle → store (with at-least-one guard)
        .onChange(of: showFiveHour) { _, new in syncMetric(.fiveHour, on: new, revert: { showFiveHour = true }) }
        .onChange(of: showSevenDay) { _, new in syncMetric(.sevenDay, on: new, revert: { showSevenDay = true }) }
        .onChange(of: showSonnet) { _, new in syncMetric(.sonnet, on: new, revert: { showSonnet = true }) }
        .onChange(of: showPacing) { _, new in
            withAnimation(.easeInOut(duration: 0.2)) {
                syncMetric(.pacing, on: new, revert: { showPacing = true })
            }
        }
        // Sync: store → local toggles (for external changes, e.g. from MenuBar popover)
        .onChange(of: settingsStore.pinnedMetrics) { _, metrics in
            if showFiveHour != metrics.contains(.fiveHour) { showFiveHour = metrics.contains(.fiveHour) }
            if showSevenDay != metrics.contains(.sevenDay) { showSevenDay = metrics.contains(.sevenDay) }
            if showSonnet != metrics.contains(.sonnet) { showSonnet = metrics.contains(.sonnet) }
            if showPacing != metrics.contains(.pacing) {
                withAnimation(.easeInOut(duration: 0.2)) { showPacing = metrics.contains(.pacing) }
            }
        }
        // Sync: local slider → store (with constraint enforcement)
        .onChange(of: warningSlider) { _, new in
            let int = Int(new)
            if themeStore.warningThreshold != int {
                themeStore.warningThreshold = int
            }
            if int >= themeStore.criticalThreshold {
                themeStore.criticalThreshold = min(int + 5, 95)
            }
        }
        .onChange(of: criticalSlider) { _, new in
            let int = Int(new)
            if themeStore.criticalThreshold != int {
                themeStore.criticalThreshold = int
            }
            if int <= themeStore.warningThreshold {
                themeStore.warningThreshold = max(int - 5, 10)
            }
        }
        // Sync: store → local sliders (for external changes, e.g. theme reset)
        .onChange(of: themeStore.warningThreshold) { _, new in
            let double = Double(new)
            if warningSlider != double { warningSlider = double }
        }
        .onChange(of: themeStore.criticalThreshold) { _, new in
            let double = Double(new)
            if criticalSlider != double { criticalSlider = double }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await settingsStore.refreshNotificationStatus() }
        }
    }

    private func syncMetric(_ metric: MetricID, on: Bool, revert: @escaping () -> Void) {
        if on {
            settingsStore.pinnedMetrics.insert(metric)
        } else if settingsStore.pinnedMetrics.count > 1 {
            settingsStore.pinnedMetrics.remove(metric)
        } else {
            revert()
        }
    }
}

// MARK: - Theming Tab

private struct ThemingTab: View {
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var showResetAlert = false

    var body: some View {
        Form {
            Section("settings.theme.menubar") {
                Toggle("settings.theme.monochrome", isOn: $themeStore.menuBarMonochrome)
            }

            Section("settings.theme.preset") {
                Picker("settings.theme.preset", selection: $themeStore.selectedPreset) {
                    ForEach(ThemeColors.allPresets, id: \.key) { preset in
                        Text(preset.label).tag(preset.key)
                    }
                    Text("settings.theme.custom").tag("custom")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            if themeStore.selectedPreset == "custom" {
                Section("settings.theme.colors") {
                    themeColorPicker("settings.theme.gauge.normal", hex: $themeStore.customTheme.gaugeNormal)
                    themeColorPicker("settings.theme.gauge.warning", hex: $themeStore.customTheme.gaugeWarning)
                    themeColorPicker("settings.theme.gauge.critical", hex: $themeStore.customTheme.gaugeCritical)
                    themeColorPicker("settings.theme.pacing.chill", hex: $themeStore.customTheme.pacingChill)
                    themeColorPicker("settings.theme.pacing.ontrack", hex: $themeStore.customTheme.pacingOnTrack)
                    themeColorPicker("settings.theme.pacing.hot", hex: $themeStore.customTheme.pacingHot)
                    themeColorPicker("settings.theme.widget.bg", hex: $themeStore.customTheme.widgetBackground)
                    themeColorPicker("settings.theme.widget.text", hex: $themeStore.customTheme.widgetText)
                }
            }

            Section("settings.theme.preview") {
                HStack(spacing: 24) {
                    Spacer()
                    themePreviewGauge(
                        pct: Double(max(themeStore.warningThreshold - 15, 5)),
                        label: "settings.theme.preview.normal"
                    )
                    themePreviewGauge(
                        pct: Double(themeStore.warningThreshold + themeStore.criticalThreshold) / 2.0,
                        label: "settings.theme.preview.warning"
                    )
                    themePreviewGauge(
                        pct: Double(min(themeStore.criticalThreshold + 5, 100)),
                        label: "settings.theme.preview.critical"
                    )
                    Spacer()
                }
            }

            Section {
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Text("settings.theme.reset")
                }
                .alert("settings.theme.reset.confirm", isPresented: $showResetAlert) {
                    Button("settings.theme.reset.cancel", role: .cancel) { }
                    Button("settings.theme.reset.action", role: .destructive) {
                        themeStore.resetToDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: themeStore.selectedPreset) { oldValue, newValue in
            if newValue == "custom", let source = ThemeColors.preset(for: oldValue) {
                themeStore.customTheme = source
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
        let theme = themeStore.current
        let thresholds = themeStore.thresholds
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
}

// MARK: - Proxy Tab

private struct ProxyTab: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("settings.proxy.toggle", isOn: $settingsStore.proxyEnabled)
            } footer: {
                Text("settings.proxy.footer")
            }

            Section("settings.proxy.config") {
                LabeledContent("settings.proxy.host") {
                    TextField("127.0.0.1", text: $settingsStore.proxyHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                LabeledContent("settings.proxy.port") {
                    TextField("1080", value: $settingsStore.proxyPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80)
                }
            }
            .disabled(!settingsStore.proxyEnabled)

            Section {
                Text("settings.proxy.hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

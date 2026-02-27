import SwiftUI

struct SettingsSectionView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var updateStore: UpdateStore

    @State private var isTesting = false
    @State private var testResult: ConnectionTestResult?
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var importSuccess = false
    @State private var notifTestCooldown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(String(localized: "sidebar.settings"))

            // Connection
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardLabel(String(localized: "settings.tab.connection"))
                    HStack(spacing: 8) {
                        Circle()
                            .fill(usageStore.hasConfig && !usageStore.hasError ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(usageStore.hasConfig && !usageStore.hasError
                             ? String(localized: "settings.connected")
                             : String(localized: "settings.disconnected"))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        if isImporting {
                            ProgressView().scaleEffect(0.6)
                        }
                        Button(String(localized: "settings.redetect")) {
                            connectAutoDetect()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.blue)
                    }
                    if let message = importMessage {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(importSuccess ? .green : .orange)
                    }
                    if let result = testResult {
                        Text(result.message)
                            .font(.system(size: 11))
                            .foregroundStyle(result.success ? .green : .red)
                    }
                }
            }

            // Proxy
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.tab.proxy"))
                    darkToggle(String(localized: "settings.proxy.toggle"), isOn: $settingsStore.proxyEnabled)
                    if settingsStore.proxyEnabled {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "settings.proxy.host"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.4))
                                TextField("127.0.0.1", text: $settingsStore.proxyHost)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "settings.proxy.port"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.4))
                                TextField("1080", value: $settingsStore.proxyPort, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(width: 80)
                            }
                        }
                    }
                }
            }

            // Notifications
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.notifications.title"))
                    HStack {
                        switch settingsStore.notificationStatus {
                        case .authorized:
                            Label(String(localized: "settings.notifications.on"), systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                        case .denied:
                            Label(String(localized: "settings.notifications.off"), systemImage: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        default:
                            Label(String(localized: "settings.notifications.unknown"), systemImage: "questionmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        if settingsStore.notificationStatus == .denied {
                            Button(String(localized: "settings.notifications.open")) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings")!)
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                        Button(String(localized: "settings.notifications.test")) {
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
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                        .disabled(notifTestCooldown)
                    }
                }
            }

            // About
            glassCard {
                HStack {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    Text("TokenEater v\(version)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if updateStore.updateAvailable {
                        Text(String(localized: "update.badge"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    Button(String(localized: "update.check")) {
                        Task { await updateStore.checkForUpdate(userInitiated: true) }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .disabled(updateStore.isChecking)
                }
            }

            Spacer()
        }
        .padding(24)
        .onAppear {
            Task { await settingsStore.refreshNotificationStatus() }
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

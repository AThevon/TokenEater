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
    @State private var brewCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(String(localized: "sidebar.settings"))

            // Connection
            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardLabel(String(localized: "settings.tab.connection"))
                    HStack(spacing: 8) {
                        Circle()
                            .fill(usageStore.hasConfig && !usageStore.isDisconnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(usageStore.hasConfig && !usageStore.isDisconnected
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
                    if usageStore.errorState == .apiUnavailable {
                        Label {
                            Text("error.banner.apiunavailable.settings")
                                .font(.system(size: 11))
                        } icon: {
                            Image(systemName: "icloud.slash")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.orange.opacity(0.8))
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
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("TokenEater v\(updateStore.currentVersion)")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        if case .checking = updateStore.updateState {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 16, height: 16)
                        } else if case .upToDate = updateStore.updateState {
                            Label(String(localized: "update.uptodate"), systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        } else if let version = updateStore.updateState.availableVersion {
                            Button(String(localized: "update.available.badge \(version)")) {
                                updateStore.downloadUpdate()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(.orange)
                        } else {
                            Button(String(localized: "update.check")) {
                                updateStore.checkForUpdates()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }
                    }

                    if updateStore.brewMigrationState == .detected {
                        brewMigrationBanner
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .onAppear {
            Task { await settingsStore.refreshNotificationStatus() }
        }
    }

    private var brewMigrationBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "update.brew.detected"), systemImage: "shippingbox.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Text(String(localized: "update.brew.hint"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 8) {
                Text(updateStore.brewUninstallCommand)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(updateStore.brewUninstallCommand, forType: .string)
                    brewCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { brewCopied = false }
                } label: {
                    Image(systemName: brewCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(brewCopied ? .green : .white.opacity(0.4))
                }
                .buttonStyle(.plain)
                Spacer()
                Button(String(localized: "update.brew.dismiss")) {
                    updateStore.dismissBrewMigration()
                }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func connectAutoDetect() {
        isImporting = true
        importMessage = nil
        guard settingsStore.credentialsTokenExists() else {
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

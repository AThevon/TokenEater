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
    @State private var brewCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(
                String(localized: "sidebar.settings"),
                subtitle: String(localized: "sidebar.settings.subtitle")
            )

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
                    if usageStore.errorState == .rateLimited {
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

            // Update (placed right under Connection so the user spots a
            // pending version straight away).
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

            // General (Launch at login + replay onboarding)
            glassCard {
                VStack(alignment: .leading, spacing: 12) {
                    cardLabel(String(localized: "settings.general.title"))
                    darkToggle(String(localized: "settings.launchAtLogin"), isOn: $settingsStore.launchAtLoginEnabled)
                    Text(String(localized: "settings.launchAtLogin.hint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().opacity(0.12)

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(localized: "settings.general.replayOnboarding"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                            Text(String(localized: "settings.general.replayOnboarding.hint"))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button {
                            settingsStore.hasCompletedOnboarding = false
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(String(localized: "settings.general.replayOnboarding.action"))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.blue.opacity(0.18))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
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

            // Refresh interval
            glassCard {
                VStack(alignment: .leading, spacing: 8) {
                    cardLabel(String(localized: "settings.refresh.title"))
                    HStack {
                        Text(String(localized: "settings.refresh.interval"))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(formatInterval(settingsStore.refreshInterval))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settingsStore.refreshInterval) },
                            set: { settingsStore.refreshInterval = Int($0) }
                        ),
                        in: 180...900,
                        step: 60
                    )
                    if settingsStore.refreshInterval < 300 {
                        Label {
                            Text(String(localized: "settings.refresh.warning"))
                                .font(.system(size: 10))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.orange.opacity(0.8))
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

    private func formatInterval(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return "\(minutes) min"
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

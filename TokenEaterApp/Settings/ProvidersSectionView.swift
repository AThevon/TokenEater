import SwiftUI

/// Providers: who TokenEater watches, and what each one actually brings.
///
/// One card per provider, then the app-level action, then the coverage matrix.
/// The two halves belong together: turning OpenAI on is the moment the
/// question "so what do I get" becomes live, and answering it three screens
/// away in a help page is how the app ended up feeling like it did something
/// different depending on the provider without ever saying so.
/// The two provider cards on their own, for hosts that bring their own
/// framing: the what's-new step, which already explains itself above them.
struct ProvidersSectionProviders: View {
    var body: some View {
        ProvidersSectionView(showsCoverage: false)
    }
}

struct ProvidersSectionView: View {
    /// Settings shows the matrix under the cards; the what's-new step has its
    /// own pane for it and would be repeating itself.
    var showsCoverage: Bool = true

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var codexStore: CodexUsageStore
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var isRedetecting = false
    @State private var claudeMessage: String?
    @State private var claudeSucceeded = false
    @State private var isTestingCodex = false
    @State private var codexResult: ConnectionTestResult?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                cardLabel(String(localized: "settings.providers.title"))

                ProviderCard(
                    provider: .claude,
                    name: "Claude",
                    isEnabled: settingsStore.claudeEnabled,
                    isLive: settingsStore.claudeEnabled && usageStore.hasConfig && usageStore.errorState == .none,
                    status: claudeStatus,
                    lockedReason: lockedReason(for: .claude),
                    enabled: $settingsStore.claudeEnabled
                ) {
                    claudeActions
                }
                resultLine(claudeMessage, success: claudeSucceeded)
                if usageStore.errorState == .rateLimited {
                    Label {
                        Text("error.banner.apiunavailable.settings").font(.system(size: 11))
                    } icon: {
                        Image(systemName: "icloud.slash").font(.system(size: 10))
                    }
                    .foregroundStyle(.orange.opacity(0.8))
                    .padding(.horizontal, DS.Spacing.xs)
                }

                ProviderCard(
                    provider: .codex,
                    name: "OpenAI Codex",
                    isEnabled: settingsStore.codexEnabled,
                    isLive: settingsStore.codexEnabled
                        && codexStore.authState.isTrackable
                        && !codexStore.authState.isExpired(),
                    status: codexStore.connectionStatus,
                    lockedReason: lockedReason(for: .codex),
                    enabled: $settingsStore.codexEnabled
                ) {
                    codexActions
                }
                resultLine(codexResult?.message, success: codexResult?.success ?? false)

                // App-level, not provider-level: it reports on the whole
                // install, and sitting inside one provider's card implied it
                // only covered that one.
                HStack {
                    Spacer()
                    CopyDiagnosticButton()
                }
                .padding(.top, DS.Spacing.xxs)
            }

            if showsCoverage {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("coverage.subtitle")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    CoverageMatrixView()
                }
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card)
                        .fill(DS.Palette.bgElevated.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.card)
                                .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Per-provider actions

    /// One label for both. "Re-detect" and "Test connection" described two
    /// implementations of the same promise: check this provider is working.
    /// Two words for one idea is how a settings screen stops looking designed.
    @ViewBuilder
    private var claudeActions: some View {
        checkButton(isRunning: isRedetecting, action: redetectClaude)
    }

    @ViewBuilder
    private var codexActions: some View {
        checkButton(isRunning: isTestingCodex, action: testCodex)
    }

    @ViewBuilder
    private func checkButton(isRunning: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            if isRunning {
                ProgressView().controlSize(.small).tint(DS.Palette.textSecondary)
            }
            darkButton("settings.providers.check", action: action)
                .disabled(isRunning)
                .opacity(isRunning ? 0.5 : 1)
        }
    }

    /// Results sit under the card rather than inside it, so a card never
    /// changes height just because you pressed its button.
    @ViewBuilder
    private func resultLine(_ message: String?, success: Bool) -> some View {
        if let message {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(success ? .green : .orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Spacing.xs)
        }
    }

    // MARK: - State

    /// The last provider on cannot be turned off: with none left there is
    /// nothing to show. The switch is disabled rather than hidden, so the
    /// control stays where the eye expects it, and the reason is said inside
    /// that provider's own card instead of floating under both.
    private func lockedReason(for provider: MetricProvider) -> String {
        settingsStore.activeProviders == [provider]
            ? String(localized: "settings.providers.lastOne")
            : ""
    }

    private var claudeStatus: String {
        if usageStore.errorState == .tokenUnavailable {
            return String(localized: "codex.status.notInstalled.claude")
        }
        if !usageStore.hasConfig {
            return String(localized: "settings.providers.claude.connecting")
        }
        var status = String(localized: "settings.providers.claude.connected")
        if usageStore.planType != .unknown {
            status += " · " + usageStore.planType.displayLabel
        }
        if let org = usageStore.organizationName, !org.isEmpty {
            status += " · " + org
        }
        return status
    }

    private func redetectClaude() {
        isRedetecting = true
        claudeMessage = nil
        guard settingsStore.credentialsTokenExists() else {
            isRedetecting = false
            claudeMessage = String(localized: "connect.noclaudecode")
            claudeSucceeded = false
            return
        }
        Task {
            let result = await usageStore.connectAutoDetect()
            isRedetecting = false
            if result.success {
                claudeMessage = String(localized: "connect.oauth.success")
                claudeSucceeded = true
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.reloadConfig(thresholds: themeStore.thresholds)
                themeStore.syncToSharedFile()
            } else {
                claudeMessage = result.message
                claudeSucceeded = false
            }
        }
    }

    private func testCodex() {
        isTestingCodex = true
        codexResult = nil
        Task {
            codexStore.handleAuthChange()
            codexResult = await codexStore.testConnection()
            isTestingCodex = false
        }
    }
}

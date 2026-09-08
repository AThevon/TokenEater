import SwiftUI

struct CodexSectionView: View {
    @EnvironmentObject private var codexStore: CodexUsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Label("Codex", systemImage: "terminal")
                    .font(DS.Typography.title2)
                if codexStore.planType != .unknown {
                    Text(codexStore.planType.displayLabel)
                        .font(DS.Typography.micro)
                        .foregroundStyle(codexStore.planType.badgeColor)
                }
                Spacer()
                if codexStore.isLoading { ProgressView().controlSize(.small) }
                if let lastUpdate = codexStore.lastUpdate {
                    Text(lastUpdate, style: .relative)
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Button {
                    codexStore.handleAuthChange()
                    Task { await codexStore.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(codexStore.isLoading)
                .help(String(localized: "contextmenu.refresh"))
            }
            if codexStore.hasError {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(errorMessage)
                        .font(DS.Typography.label)
                        .foregroundStyle(.orange)
                    CopyDiagnosticButton()
                }
            }
            if codexStore.limitReached {
                Label(String(localized: "codex.limitReached"), systemImage: "exclamationmark.circle.fill")
                    .font(DS.Typography.label)
                    .foregroundStyle(.red)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: DS.Spacing.sm) {
                ForEach(codexStore.windows) { window in
                    MetricTile(
                        id: "codex-" + window.id,
                        label: window.label,
                        icon: window.kind == .session ? "timer" : "calendar",
                        pct: window.pct,
                        resetText: resetText(for: window),
                        resetDate: window.resetDate,
                        windowDuration: window.windowDuration,
                        smartEnabled: settingsStore.smartColorEnabled,
                        pacingMargin: Double(settingsStore.pacingMargin),
                        smartProfile: settingsStore.smartColorProfile,
                        themeStore: themeStore,
                        insights: nil,
                        insightsLoaded: true
                    )
                }
            }
            if codexStore.windows.isEmpty, !codexStore.hasError, !codexStore.isLoading {
                Text("codex.test.noWindows")
                    .font(DS.Typography.label)
                    .foregroundStyle(.secondary)
            }
            if let pacing = codexStore.weekly?.pacing {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("codex.pacing.weekly")
                        .font(DS.Typography.label)
                    PacingBar(
                        actual: pacing.actualUsage, expected: pacing.expectedUsage,
                        zone: pacing.zone, gradient: themeStore.current.pacingGradient(for: pacing.zone)
                    )
                    Text(pacing.message)
                        .font(DS.Typography.label)
                        .foregroundStyle(.secondary)
                }
                .padding(DS.Spacing.sm)
                .dsGlass()
            }
            if let credits = codexStore.credits {
                if credits.overageLimitReached == true {
                    Text("codex.credits.cap")
                        .font(DS.Typography.label)
                        .foregroundStyle(.orange)
                } else if credits.hasCredits == true {
                    Text(credits.unlimited == true
                         ? String(localized: "codex.credits.unlimited")
                         : String(format: String(localized: "codex.credits.balance"), credits.balance ?? "—"))
                        .font(DS.Typography.label)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(DS.Palette.textPrimary)
    }

    private func resetText(for window: CodexWindowSnapshot) -> String {
        switch settingsStore.resetDisplayFormat {
        case .relative: return window.relativeReset
        case .absolute: return window.absoluteReset
        case .both: return window.relativeReset + " · " + window.absoluteReset
        }
    }

    private var errorMessage: String {
        switch codexStore.errorState {
        case .tokenUnavailable: return codexStore.connectionStatus
        case .rateLimited: return String(localized: "codex.error.rateLimited")
        case .networkError: return String(localized: "error.network.generic")
        case .none: return ""
        }
    }
}

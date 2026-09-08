import SwiftUI

struct CodexSectionView: View {
    @EnvironmentObject private var codexStore: CodexUsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm) {
                Label("Codex", systemImage: "terminal")
                    .font(DS.Typography.title1)
                if codexStore.planType != .unknown {
                    Text(codexStore.planType.displayLabel)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.input)
                                .fill(codexStore.planType.badgeColor.opacity(0.25))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.input)
                                        .stroke(codexStore.planType.badgeColor.opacity(0.5), lineWidth: 0.6)
                                )
                        )
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(DS.Palette.glassFill))
                        .overlay(Circle().stroke(DS.Palette.glassBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(codexStore.isLoading)
                .help(String(localized: "contextmenu.refresh"))
            }
            .padding(.horizontal, DS.Spacing.xs)
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
            VStack(spacing: DS.Spacing.sm) {
                ForEach(MetricsGridLayout.rows(tiles), id: \.first?.id) { row in
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(row) { tile in
                            switch tile {
                            case .window(let window):
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
                            case .pacing(let pacing):
                                CodexPacingCard(pacing: pacing)
                            }
                        }
                    }
                }
            }
            if codexStore.windows.isEmpty, !codexStore.hasError, !codexStore.isLoading {
                Text("codex.test.noWindows")
                    .font(DS.Typography.label)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: DS.Spacing.xs) {
                if codexStore.planType != .unknown {
                    DashboardStatusPill(
                        icon: "sparkles", label: String(localized: "dashboard.tier"),
                        value: codexStore.planType.displayLabel, tint: codexStore.planType.badgeColor
                    )
                }
                if let resets = codexStore.lastUsage?.resetCreditsAvailable {
                    DashboardStatusPill(
                        icon: "arrow.counterclockwise",
                        value: resets == 1
                            ? String(localized: "widget.codex.reset.single")
                            : String(format: String(localized: "widget.codex.resets"), max(0, resets)),
                        tint: resets > 0 ? .orange : DS.Palette.textTertiary
                    )
                }
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

    private enum Tile: Identifiable {
        case window(CodexWindowSnapshot)
        case pacing(PacingResult)

        var id: String {
            switch self {
            case .window(let window): "window-" + window.id
            case .pacing: "weekly-pacing"
            }
        }
    }

    private var tiles: [Tile] {
        var tiles = codexStore.windows.map(Tile.window)
        if let pacing = codexStore.weekly?.pacing {
            tiles.append(.pacing(pacing))
        }
        return tiles
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

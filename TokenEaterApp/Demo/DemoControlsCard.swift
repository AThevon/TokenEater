import SwiftUI
import AppKit

/// The multi-account demo's controls, at the top of Settings > Providers.
/// Drawn only while the demo runs (`DemoMode.isActive`), which takes a
/// `defaults write` to turn on: nobody else ever sees it.
///
/// Sample alerts per account, with the real wording; a refresh of every
/// fake account; the seeded accounts back after a Remove; and the way out.
struct DemoControlsCard: View {
    @EnvironmentObject private var accountsStore: AccountsStore
    @EnvironmentObject private var codexStore: CodexUsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var confirmsTurnOff = false

    private var home: String { ClaudeConfigDirResolver.realHome() }

    private var missingSeeded: [DemoClaudeFixture] {
        DemoFixtures.seeded.filter { fixture in
            !accountsStore.records.contains { $0.configDir == fixture.folderPath(home: home) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "theatermasks")
                    .font(.system(size: 11, weight: .semibold))
                Text("demo.title")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(DS.Palette.semanticWarning)

            Text("demo.subtitle")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(accountsStore.records) { record in
                    accountLine(record)
                }
            }

            HStack(spacing: 6) {
                smallButton("demo.refresh", systemImage: "arrow.clockwise", action: refreshAll)
                if !missingSeeded.isEmpty {
                    smallButton("demo.restore", systemImage: "arrow.uturn.backward", action: restoreSeeded)
                }
                Spacer(minLength: 0)
                smallButton("demo.turnOff", systemImage: "power") { confirmsTurnOff = true }
            }
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.semanticWarning.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(DS.Palette.semanticWarning.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        )
        .alert(String(localized: "demo.turnOff.title"), isPresented: $confirmsTurnOff) {
            Button(String(localized: "accounts.add.cancel"), role: .cancel) {}
            Button(String(localized: "demo.turnOff.action"), role: .destructive, action: turnOffAndQuit)
        } message: {
            Text("demo.turnOff.message")
        }
    }

    private func accountLine(_ record: ClaudeAccountRecord) -> some View {
        let isDemo = DemoFixtures.fixture(forFolder: record.configDir, home: home) != nil
        return HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: record.colorHex))
                .frame(width: 7, height: 7)
            Text(record.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
            Text(isDemo ? "demo.account.fake" : "demo.account.real")
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.textTertiary)
            Spacer(minLength: DS.Spacing.xs)
            // Only on fake accounts: a sample posted under a real account's
            // scope would carry its real identifiers, replace a real alert
            // and outlive the demo.
            if isDemo {
                smallButton("demo.notify.threshold", systemImage: "gauge.with.dots.needle.67percent") {
                    DemoNotifications.sendThresholdSample(
                        scope: accountsStore.notificationScope(for: record.id),
                        thresholds: themeStore.thresholds
                    )
                }
                smallButton("demo.notify.expired", systemImage: "key.slash") {
                    DemoNotifications.sendLoginExpiredSample(
                        scope: accountsStore.notificationScope(for: record.id),
                        thresholds: themeStore.thresholds
                    )
                }
            }
        }
    }

    private func smallButton(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(titleKey, systemImage: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    /// Every running fake account, and the fake Codex login, fetch now: the
    /// fixtures drift with time, so the numbers move.
    private func refreshAll() {
        let thresholds = themeStore.thresholds
        for record in accountsStore.records where !record.isPaused {
            guard DemoFixtures.fixture(forFolder: record.configDir, home: home) != nil,
                  let store = accountsStore.usageStore(for: record.id) else { continue }
            Task { await store.refresh(thresholds: thresholds, force: true) }
        }
        Task { await codexStore.refresh(thresholds: thresholds, force: true) }
    }

    /// The seeded accounts removed during the demo come back, through the
    /// same `add` path a connected account takes, with their last numbers
    /// and their place in the All layouts.
    private func restoreSeeded() {
        let now = Date()
        var restored: [ClaudeAccountRecord] = []
        for fixture in missingSeeded {
            let record = DemoFixtures.record(for: fixture, home: home, now: now)
            DemoLaunch.seedLastNumbers(
                for: fixture,
                file: SharedFileService(fileName: record.id.sharedFileName),
                startedAt: now
            )
            if accountsStore.add(record) { restored.append(record) }
        }
        DemoLaunch.seedLayouts(for: restored, into: settingsStore, home: home)
    }

    /// The switch goes now; the cleanup runs at the next launch, before any
    /// store starts.
    private func turnOffAndQuit() {
        UserDefaults.standard.removeObject(forKey: DemoMode.flagKey)
        NSApp.terminate(nil)
    }
}

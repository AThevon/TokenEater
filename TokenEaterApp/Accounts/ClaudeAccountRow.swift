import SwiftUI

/// One tracked Claude account inside the Claude card of Settings > Providers,
/// shown once two or more accounts are tracked.
///
/// Its mark, name, plan and folder; where it stands (`AccountHealth`), with
/// the one action that fixes it when there is one; its own Check and Reset;
/// and, for an added account, a Track switch (pause) and Remove. The main
/// account stops only with Claude itself, so it has neither.
struct ClaudeAccountRow<FolderLine: View>: View {
    let record: ClaudeAccountRecord
    @ObservedObject var store: UsageStore
    /// The main account's folder line carries its own picker (#294); an
    /// added account's is plain text.
    @ViewBuilder let folderLine: () -> FolderLine

    @EnvironmentObject private var accountsStore: AccountsStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var tracking = true
    @State private var isEditing = false
    @State private var draftName = ""
    @State private var draftColor = ""
    @State private var confirmsRemoval = false
    @State private var isChecking = false
    @State private var isResetting = false
    @State private var resultMessage: String?
    @State private var resultSucceeded = false

    private var home: String { ClaudeConfigDirResolver.realHome() }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            topLine
            healthLine
            HStack(alignment: .center, spacing: 6) {
                folderLine()
                Spacer(minLength: DS.Spacing.xs)
                if !record.isPaused {
                    providerResetButton(isRunning: isResetting, action: reset)
                    providerCheckButton(isRunning: isChecking, action: check)
                }
            }
            if let resultMessage {
                Text(resultMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(resultSucceeded ? DS.Palette.semanticSuccess : DS.Palette.semanticWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color.white.opacity(record.isPaused ? 0.015 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(health.needsAttention
                                ? DS.Palette.semanticWarning.opacity(0.28)
                                : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .onAppear { tracking = !record.isPaused }
        .onChange(of: record.isPaused) { _, paused in tracking = !paused }
        .onChange(of: tracking) { _, isOn in
            guard isOn == record.isPaused else { return }
            accountsStore.setPaused(!isOn, for: record.id)
        }
        .alert(
            String(format: String(localized: "accounts.remove.title"), record.name),
            isPresented: $confirmsRemoval
        ) {
            Button(String(localized: "accounts.add.cancel"), role: .cancel) {}
            Button(String(localized: "accounts.remove.action"), role: .destructive) {
                accountsStore.remove(record.id)
            }
        } message: {
            Text("accounts.remove.message")
        }
    }

    // MARK: - Top line

    private var topLine: some View {
        HStack(spacing: DS.Spacing.xs) {
            AccountDot(colorHex: record.colorHex, size: 10)
            Text(record.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(record.isPaused ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                .lineLimit(1)
                .help(record.name)
            if record.id.isMain {
                tag(String(localized: "accounts.row.main"))
            }
            if store.planType != .unknown {
                tag(store.planType.displayLabel)
            }
            Spacer(minLength: DS.Spacing.xs)
            if !record.id.isMain {
                Toggle("", isOn: $tracking)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .scaleEffect(0.7)
                    .frame(width: 34)
                    .help(tracking
                          ? String(localized: "accounts.row.tracking")
                          : String(localized: "accounts.row.paused.help"))
            }
            actionsMenu
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(DS.Palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    private var actionsMenu: some View {
        Menu {
            Button(String(localized: "accounts.row.edit")) { beginEditing() }
            if !record.id.isMain {
                Divider()
                Button(String(localized: "accounts.row.remove"), role: .destructive) {
                    confirmsRemoval = true
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // Padding and hit area on the Menu itself: under the borderless style
        // AppKit redraws the label and drops anything applied inside it.
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help(String(localized: "accounts.row.more"))
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            editor
        }
    }

    // MARK: - Name and colour

    private var editor: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("accounts.details.name")
                .font(DS.Typography.micro)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(DS.Palette.textTertiary)
            AccountNameField(name: $draftName, onCommit: saveEdits)
            Text("accounts.details.color")
                .font(DS.Typography.micro)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(DS.Palette.textTertiary)
            AccountColorPicker(
                colorHex: $draftColor,
                taken: accountsStore.records.filter { $0.id != record.id }.map(\.colorHex),
                riskColors: themeStore.current.gaugeRiskColors
            )
        }
        .padding(DS.Spacing.md)
        .frame(width: 330)
        .onChange(of: draftColor) { _, _ in saveEdits() }
        .onDisappear(perform: saveEdits)
    }

    private func beginEditing() {
        draftName = record.name
        draftColor = record.colorHex
        isEditing = true
    }

    private func saveEdits() {
        guard !draftColor.isEmpty else { return }
        let name = draftName
        let color = draftColor
        accountsStore.update(record.id) { record in
            record.name = name
            record.colorHex = color
        }
    }

    // MARK: - Health

    private var command: String {
        record.configDir.map { ClaudeConfigDirResolver.loginCommand(forConfigDir: $0, home: home) } ?? "claude"
    }

    private var health: AccountHealth {
        AccountHealth.resolve(
            errorState: store.errorState,
            diagnostic: store.tokenDiagnostic,
            loginExpiredSince: store.loginExpiredSince,
            identityState: store.identityState,
            isPaused: record.isPaused,
            lastUpdate: store.lastUpdate,
            folderExists: record.configDir.map { FileManager.default.fileExists(atPath: $0) } ?? true,
            command: command,
            names: Dictionary(uniqueKeysWithValues: accountsStore.records.map { ($0.id, $0.name) })
        )
    }

    @ViewBuilder
    private var healthLine: some View {
        let health = self.health
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(healthColor(health))
                    .frame(width: 6, height: 6)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(healthText(health))
                    .font(.system(size: 11))
                    .foregroundStyle(health.needsAttention ? DS.Palette.textPrimary.opacity(0.85) : DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                healthAction(health)
            }
            switch health {
            case .loginExpired(_, let command), .noLogin(let command):
                CommandBox(command: command)
            default:
                EmptyView()
            }
        }
    }

    private func healthColor(_ health: AccountHealth) -> Color {
        switch health {
        case .upToDate: return DS.Palette.semanticSuccess
        case .checking, .identityPending: return DS.Palette.semanticInfo
        case .paused: return DS.Palette.textTertiary
        case .rateLimited, .network: return DS.Palette.semanticWarning
        default: return DS.Palette.semanticError
        }
    }

    private func healthText(_ health: AccountHealth) -> String {
        switch health {
        case .checking:
            return String(localized: "accounts.health.checking")
        case .upToDate(let date):
            return String(format: String(localized: "accounts.health.upToDate"), date.relativeFormatted)
        case .paused(let lastUpdate):
            guard let lastUpdate else { return String(localized: "accounts.health.paused") }
            return String(
                format: String(localized: "accounts.health.paused.numbers"),
                store.fiveHourPct, store.sevenDayPct, Self.stamp(lastUpdate)
            )
        case .loginExpired(let since, _):
            guard let since else { return String(localized: "accounts.health.expired") }
            return String(format: String(localized: "accounts.health.expired.since"), since.relativeFormatted)
        case .accessDenied:
            return String(localized: "accounts.health.accessDenied")
        case .timedOut:
            return String(localized: "accounts.health.timedOut")
        case .noLogin:
            return String(localized: "accounts.health.noLogin")
        case .folderMissing:
            return String(localized: "accounts.health.folderMissing")
        case .rateLimited:
            return String(localized: "accounts.health.rateLimited")
        case .network:
            return String(localized: "accounts.health.network")
        case .identityPending:
            return String(localized: "accounts.health.identityPending")
        case .identityConflict(let verdict, let other, let source):
            switch verdict {
            case .belongsTo:
                let name = other ?? String(localized: "accounts.health.anotherAccount")
                if record.id.isMain {
                    guard let source else {
                        return String(format: String(localized: "accounts.health.mainMoved"), name)
                    }
                    return String(format: String(localized: "accounts.health.mainMoved.source"), name, Self.label(for: source))
                }
                return String(format: String(localized: "accounts.health.sameAs"), name)
            case .changed, .accepted, .untracked:
                return String(localized: "accounts.health.changed")
            }
        }
    }

    @ViewBuilder
    private func healthAction(_ health: AccountHealth) -> some View {
        switch health {
        case .accessDenied, .timedOut, .network:
            smallButton(String(localized: "accounts.health.retry"), action: check)
        case .identityConflict(.changed(let digest), _, _):
            smallButton(String(localized: "accounts.health.useThisAccount")) {
                guard accountsStore.acceptIdentity(digest, for: record.id) else { return }
                Task { await store.refresh(thresholds: themeStore.thresholds, force: true) }
            }
        default:
            EmptyView()
        }
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.white.opacity(0.08))
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    /// "09:12" today, "12 Oct 09:12" before.
    private static func stamp(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    private static func label(for source: TokenSource) -> String {
        switch source {
        case .keychainCLI: return String(localized: "accounts.source.keychain")
        case .credentialsFile: return ".credentials.json"
        case .claudeDesktop: return "Claude Desktop"
        }
    }

    // MARK: - Actions

    private func check() {
        isChecking = true
        resultMessage = nil
        Task {
            store.proxyConfig = settingsStore.proxyConfig
            store.handleTokenChange()
            let result = await store.connectAutoDetect()
            isChecking = false
            resultSucceeded = result.success
            resultMessage = result.success ? String(localized: "connect.oauth.success") : result.message
            if result.success {
                await store.refresh(thresholds: themeStore.thresholds, force: true)
            }
        }
    }

    private func reset() {
        isResetting = true
        resultMessage = nil
        Task {
            store.proxyConfig = settingsStore.proxyConfig
            let result = await store.resetConnection(thresholds: themeStore.thresholds)
            isResetting = false
            resultSucceeded = result.success
            resultMessage = result.success ? String(localized: "settings.providers.reset.done") : result.message
            if result.success, record.id.isMain {
                store.reloadConfig(thresholds: themeStore.thresholds)
                themeStore.syncToSharedFile()
            }
        }
    }
}

extension ClaudeAccountRow where FolderLine == AccountFolderLabel {
    init(record: ClaudeAccountRecord, store: UsageStore) {
        self.init(record: record, store: store) {
            AccountFolderLabel(record: record, maskedEmail: store.maskedEmail, organization: store.organizationName)
        }
    }
}

/// The organization and masked email of the login an account's store reads,
/// followed live. Settings is the only place either shows.
struct AccountLoginFacts: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        let facts = [store.organizationName, store.maskedEmail].compactMap { $0 }.filter { !$0.isEmpty }
        if !facts.isEmpty {
            HStack(spacing: 6) {
                ForEach(facts, id: \.self) { fact in
                    Text(fact)
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

/// The folder an account reads, in its `~` form, with the masked email and
/// organization of its login. Settings is the only place either shows.
struct AccountFolderLabel: View {
    let record: ClaudeAccountRecord
    let maskedEmail: String?
    let organization: String?

    var body: some View {
        let home = ClaudeConfigDirResolver.realHome()
        let folder = ClaudeConfigDirResolver.displayPath(
            record.configDir ?? ClaudeConfigDirResolver.defaultDirectory(home: home),
            home: home
        )
        HStack(spacing: 6) {
            Label(folder, systemImage: "folder")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(folder)
            ForEach([organization, maskedEmail].compactMap { $0 }.filter { !$0.isEmpty }, id: \.self) { fact in
                Text(fact)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

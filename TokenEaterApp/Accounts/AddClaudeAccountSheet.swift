import SwiftUI
import AppKit

/// Adds a Claude account, in two steps.
///
/// 1. Where does it live: the `~/.claude-*` folders the scanner found (their
///    files, and whether a Keychain item exists for them, asked of its
///    attributes alone), or any folder picked by hand. Nothing is read yet.
/// 2. Connect reads that folder's login, once, and identifies it. The user
///    then names the account, picks its colour and decides whether it joins
///    the menu bar, with a preview of the result.
///
/// Nothing is stored before Done.
struct AddClaudeAccountSheet: View {
    @Binding var isPresented: Bool

    @EnvironmentObject private var accountsStore: AccountsStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var codexStore: CodexUsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var vendorStatusStore: VendorStatusStore

    private enum Step: Equatable {
        case folder
        case details(PendingAccount)
    }

    @State private var step: Step = .folder

    // Step 1
    @State private var candidates: [ConfigDirCandidate] = []
    @State private var pickedPaths: Set<String> = []
    @State private var selectedPath: String?
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var isConnecting = false
    @State private var failure: AccountConnectResult?
    @State private var scanTask: Task<Void, Never>?
    @State private var connectTask: Task<Void, Never>?

    // Step 2
    @State private var name = ""
    @State private var colorHex = AccountPalette.presets[1]
    @State private var mainName = ""
    @State private var addToMenuBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch step {
            case .folder:
                folderStep
                    .transition(.opacity)
            case .details(let pending):
                detailsStep(pending)
                    .transition(.opacity)
            }
        }
        .frame(width: 540)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.55))
        .animation(DS.Motion.easeOut, value: step)
        .onAppear(perform: scan)
        .onDisappear {
            scanTask?.cancel()
            connectTask?.cancel()
        }
    }

    // MARK: - Header and footer

    private func header(title: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ProviderGlyph(provider: .claude, size: 13)
                        .foregroundStyle(DS.Palette.brandPrimary)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, 18)
        .padding(.bottom, DS.Spacing.sm)
    }

    private func footer<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Spacer()
            trailing()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.02))
        .overlay(Rectangle().fill(DS.Palette.glassBorderLo).frame(height: 1), alignment: .top)
    }

    // MARK: - Step 1: folder

    private var selected: ConfigDirCandidate? {
        candidates.first { $0.path == selectedPath }
    }

    private var folderStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(
                title: String(localized: "accounts.add.title"),
                subtitle: String(localized: "accounts.add.subtitle")
            )

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    sectionLabel("accounts.add.folders")
                    Spacer()
                    if isScanning {
                        ProgressView().controlSize(.small).tint(DS.Palette.textSecondary)
                    } else {
                        Button(action: scan) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "accounts.add.rescan"))
                    }
                }

                candidateList

                Button(action: chooseFolder) {
                    Label(String(localized: "accounts.add.choose"), systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isConnecting)

                if let failure {
                    ConnectFailureView(result: failure)
                        .transition(.opacity)
                }

                Label {
                    Text("accounts.add.keychainNote")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "key.fill")
                }
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.md)

            footer {
                Button(String(localized: "accounts.add.cancel")) { isPresented = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .padding(.horizontal, DS.Spacing.sm)
                SheetPrimaryButton(
                    title: String(localized: "accounts.add.connect"),
                    isBusy: isConnecting,
                    isEnabled: selected?.hasLogin == true && !isConnecting,
                    action: connect
                )
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var candidateList: some View {
        if candidates.isEmpty {
            HStack(spacing: DS.Spacing.xs) {
                if !hasScanned {
                    ProgressView().controlSize(.small).tint(DS.Palette.textSecondary)
                    Text("accounts.add.scanning")
                } else {
                    Image(systemName: "tray")
                    Text("accounts.add.empty")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(DS.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Spacing.sm)
            .background(listBackground)
        } else {
            ScrollView(.vertical, showsIndicators: candidates.count > 4) {
                VStack(spacing: 6) {
                    ForEach(candidates) { candidate in
                        CandidateRow(
                            candidate: candidate,
                            isSelected: candidate.path == selectedPath,
                            home: ClaudeConfigDirResolver.realHome()
                        ) {
                            selectedPath = candidate.path
                            failure = nil
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 236)
            .fixedSize(horizontal: false, vertical: candidates.count <= 3)
            .background(listBackground)
        }
    }

    private var listBackground: some View {
        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .fill(Color.black.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
            )
    }

    private func scan() {
        scanTask?.cancel()
        isScanning = true
        let scanner = accountsStore.scanner
        let tracked = accountsStore.trackedPaths
        scanTask = Task {
            let found = await Task.detached(priority: .userInitiated) {
                scanner.candidates(excluding: tracked)
            }.value
            guard !Task.isCancelled else { return }
            // A folder picked by hand stays on the list even when the scan
            // would not have offered it.
            let kept = candidates.filter { pickedPaths.contains($0.path) && !found.map(\.path).contains($0.path) }
            candidates = kept + found
            isScanning = false
            hasScanned = true
            if selectedPath.map({ path in !candidates.contains { $0.path == path } }) ?? true {
                selectedPath = candidates.first(where: \.hasLogin)?.path
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: ClaudeConfigDirResolver.realHome(), isDirectory: true)
        panel.prompt = String(localized: "accounts.add.choose.prompt")
        panel.message = String(localized: "accounts.add.choose.message")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        if accountsStore.isTracked(folder: path) {
            failure = .alreadyTracked
            return
        }
        let scanner = accountsStore.scanner
        Task {
            let candidate = await Task.detached(priority: .userInitiated) { scanner.inspect(path: path) }.value
            pickedPaths.insert(candidate.path)
            candidates.removeAll { $0.path == candidate.path }
            candidates.insert(candidate, at: 0)
            hasScanned = true
            selectedPath = candidate.path
            failure = nil
        }
    }

    private func connect() {
        guard let candidate = selected, candidate.hasLogin else { return }
        connectTask?.cancel()
        isConnecting = true
        failure = nil
        let proxy = settingsStore.proxyConfig
        connectTask = Task {
            let result = await accountsStore.connect(
                configDir: candidate.path,
                knownService: candidate.matchedService,
                proxyConfig: proxy
            )
            guard !Task.isCancelled else { return }
            isConnecting = false
            NSApp.activate(ignoringOtherApps: true)
            guard case .ready(let pending) = result else {
                failure = result
                return
            }
            name = pending.proposedName
            colorHex = pending.proposedColorHex
            mainName = accountsStore.mainRecord.name
            addToMenuBar = true
            step = .details(pending)
        }
    }

    // MARK: - Step 2: details

    /// Names only show once two accounts are tracked, which is what this
    /// sheet is about to make true: the main account gets its say too.
    private var asksForMainName: Bool { accountsStore.records.count == 1 }

    private func detailsStep(_ pending: PendingAccount) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(
                title: String(localized: "accounts.details.title"),
                subtitle: String(localized: "accounts.details.subtitle")
            )

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                identityCard(pending)

                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("accounts.details.name")
                    AccountNameField(name: $name)
                }

                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("accounts.details.color")
                    AccountColorPicker(colorHex: $colorHex, taken: accountsStore.records.map(\.colorHex))
                    Text("accounts.details.color.hint")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if asksForMainName {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("accounts.details.mainName")
                        HStack(spacing: DS.Spacing.xs) {
                            AccountDot(colorHex: accountsStore.mainRecord.colorHex, size: 10)
                            AccountNameField(name: $mainName)
                        }
                        Text("accounts.details.mainName.hint")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                menuBarChoice(pending)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.md)

            footer {
                Button(String(localized: "accounts.details.back")) {
                    step = .folder
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .padding(.horizontal, DS.Spacing.sm)
                SheetPrimaryButton(
                    title: String(localized: "accounts.details.done"),
                    isBusy: false,
                    isEnabled: true
                ) {
                    finish(pending)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func identityCard(_ pending: PendingAccount) -> some View {
        let shownName = AccountNameRules.sanitize(name, fallback: pending.proposedName)
        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            AccountDot(colorHex: colorHex, size: 12)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(shownName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.brandPrimary)
                    Text("accounts.details.connected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Palette.brandPrimary.opacity(0.9))
                }
                FlowChips(items: identityFacts(pending))
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(DS.Palette.glassBorder, lineWidth: 1)
                )
        )
    }

    private func identityFacts(_ pending: PendingAccount) -> [String] {
        var facts: [String] = []
        if pending.plan != .unknown { facts.append(pending.plan.displayLabel) }
        if let org = pending.organizationName, !org.isEmpty { facts.append(org) }
        if let email = pending.maskedEmail { facts.append(email) }
        facts.append(ClaudeConfigDirResolver.displayPath(pending.configDir, home: ClaudeConfigDirResolver.realHome()))
        return facts
    }

    private func menuBarChoice(_ pending: PendingAccount) -> some View {
        let preview = MenuBarRenderer.RenderData.previewAddingAccount(
            AccountID(rawValue: "acct-preview"),
            usage: usageStore,
            theme: themeStore,
            settings: settingsStore,
            vendor: vendorStatusStore,
            codex: codexStore,
            accounts: accountsStore
        )
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Toggle(isOn: $addToMenuBar) {
                Text("accounts.details.addToMenuBar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Palette.textPrimary)
            }
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 6) {
                previewRow(label: String(localized: "accounts.details.preview.now"), data: preview.before)
                if addToMenuBar {
                    previewRow(
                        label: String(
                            format: String(localized: "accounts.details.preview.with"),
                            AccountNameRules.sanitize(name, fallback: pending.proposedName)
                        ),
                        data: preview.after
                    )
                    .transition(.opacity)
                }
            }
            .padding(DS.Spacing.xs)
            .background(listBackground)

            Text(addToMenuBar
                 ? String(localized: "accounts.details.preview.hint")
                 : String(localized: "accounts.details.preview.off"))
                .font(.system(size: 10))
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(DS.Motion.easeOut, value: addToMenuBar)
    }

    private func previewRow(label: String, data: MenuBarRenderer.RenderData) -> some View {
        let image = MenuBarRenderer.renderWithHitRects(data).image
        let scale: CGFloat = 1.5
        return HStack(spacing: DS.Spacing.xs) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .frame(height: image.size.height * scale + 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: "#1E1E1E"))
            )
        }
    }

    private func finish(_ pending: PendingAccount) {
        let renamesMain = asksForMainName
        guard let record = accountsStore.commit(pending, name: name, colorHex: colorHex) else {
            failure = .alreadyTracked
            step = .folder
            scan()
            return
        }
        if renamesMain {
            // `update` keeps the current name when the field was emptied.
            accountsStore.update(.main) { $0.name = mainName }
        }
        settingsStore.seedAccount(record.id, addToMenuBar: addToMenuBar)
        isPresented = false
    }

    // MARK: - Pieces

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(DS.Typography.micro)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(DS.Palette.textTertiary)
    }
}

// MARK: - Candidate row

private struct CandidateRow: View {
    let candidate: ConfigDirCandidate
    let isSelected: Bool
    let home: String
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? DS.Palette.brandPrimary : DS.Palette.textTertiary)
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                Text(candidate.displayPath)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(candidate.displayPath)
                Spacer(minLength: DS.Spacing.xs)
                if let activity = candidate.lastActivity {
                    Text(String(format: String(localized: "accounts.add.activity"), activity.relativeFormatted))
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 5) {
                Circle()
                    .fill(candidate.hasLogin ? DS.Palette.semanticSuccess : DS.Palette.semanticWarning)
                    .frame(width: 6, height: 6)
                Text(statusKey)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .padding(.leading, 20)

            if !candidate.hasLogin, candidate.exists {
                VStack(alignment: .leading, spacing: 4) {
                    CommandBox(command: ClaudeConfigDirResolver.loginCommand(forConfigDir: candidate.path, home: home))
                    Text("accounts.add.thenLogin")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                .fill(isSelected ? DS.Palette.brandPrimary.opacity(0.08)
                      : (hovering ? Color.white.opacity(0.04) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                        .stroke(isSelected ? DS.Palette.brandPrimary.opacity(0.35) : .clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
    }

    private var statusKey: LocalizedStringKey {
        if !candidate.exists { return "accounts.add.status.missing" }
        if candidate.matchedService != nil { return "accounts.add.status.keychain" }
        if candidate.hasCredentialsFile { return "accounts.add.status.file" }
        return "accounts.add.status.none"
    }
}

// MARK: - Shared pieces

/// Why connecting a folder did not work, with the command to run when one
/// exists. Shared by the add sheet and the main account's folder picker.
struct ConnectFailureView: View {
    let result: AccountConnectResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.system(size: 11))
            .foregroundStyle(DS.Palette.semanticWarning)

            if let command {
                CommandBox(command: command)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                .fill(DS.Palette.semanticWarning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                        .stroke(DS.Palette.semanticWarning.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var message: String {
        switch result {
        case .ready:
            return ""
        case .noLogin:
            return String(localized: "accounts.connect.noLogin")
        case .accessDenied:
            return String(localized: "accounts.connect.accessDenied")
        case .timedOut:
            return String(localized: "accounts.connect.timedOut")
        case .expired:
            return String(localized: "accounts.connect.expired")
        case .duplicate(let other):
            return String(format: String(localized: "accounts.connect.duplicate"), other.name)
        case .alreadyTracked:
            return String(localized: "accounts.connect.alreadyTracked")
        case .network(let detail):
            return String(format: String(localized: "accounts.connect.network"), detail)
        }
    }

    private var command: String? {
        switch result {
        case .noLogin(let command), .expired(let command): return command
        default: return nil
        }
    }
}

/// A shell command shown as text the user can select, with a Copy button.
struct CommandBox: View {
    let command: String

    @State private var copied = false

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.Palette.textPrimary.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
            } label: {
                Label(
                    copied ? String(localized: "accounts.command.copied") : String(localized: "accounts.command.copy"),
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(copied ? DS.Palette.brandPrimary : DS.Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

/// The sheet's main action: a filled capsule, with a spinner while it runs.
struct SheetPrimaryButton: View {
    let title: String
    let isBusy: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(.black.opacity(0.7))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? Color.black.opacity(0.85) : DS.Palette.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isEnabled ? DS.Palette.brandPrimary : Color.white.opacity(0.06))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// Facts about an account as small capsules, wrapping when they do not fit.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) { chips }
            VStack(alignment: .leading, spacing: 4) { chips }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(items, id: \.self) { item in
            Text(item)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))
                )
        }
    }
}

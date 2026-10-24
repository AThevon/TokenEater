import SwiftUI
import AppKit

/// "Folder: ~/.claude · Change…", the main account's config folder (#294).
///
/// Most people never touch it: Claude Code keeps its login in `~/.claude`.
/// Someone who runs Claude Code with `CLAUDE_CONFIG_DIR` set points the main
/// account at that folder here, and its token, History and Agent Watchers
/// follow it.
struct MainConfigDirRow: View {
    @EnvironmentObject private var accountsStore: AccountsStore

    @State private var showsPicker = false
    @State private var hovering = false

    var body: some View {
        let home = ClaudeConfigDirResolver.realHome()
        let folder = ClaudeConfigDirResolver.displayPath(
            accountsStore.mainRecord.configDir ?? ClaudeConfigDirResolver.defaultDirectory(home: home),
            home: home
        )
        HStack(spacing: 5) {
            Image(systemName: "folder")
                .font(.system(size: 10))
            Text(String(format: String(localized: "accounts.mainFolder.label"), folder))
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(folder)
            Text("·")
            Button {
                showsPicker = true
            } label: {
                Text("accounts.mainFolder.change")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hovering ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                    .underline(hovering)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(String(localized: "accounts.mainFolder.change.hint"))
        }
        .foregroundStyle(DS.Palette.textTertiary)
        .sheet(isPresented: $showsPicker) {
            MainConfigDirSheet(isPresented: $showsPicker)
        }
    }
}

/// Chooses the folder the main account reads. The candidates come from the
/// same scan as the add-account sheet, run only while this sheet is open;
/// picking one reads that folder's login once, identifies it, and moves the
/// main account there only if it checks out.
struct MainConfigDirSheet: View {
    @Binding var isPresented: Bool

    @EnvironmentObject private var accountsStore: AccountsStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var candidates: [ConfigDirCandidate] = []
    @State private var hasScanned = false
    @State private var applyingPath: String?
    @State private var failure: AccountConnectResult?
    @State private var scanTask: Task<Void, Never>?
    @State private var applyTask: Task<Void, Never>?

    private var home: String { ClaudeConfigDirResolver.realHome() }
    private var isCustom: Bool { accountsStore.mainRecord.configDir != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("accounts.mainFolder.title")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text("accounts.mainFolder.subtitle")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button { isPresented = false } label: {
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

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                currentFolder

                if !candidates.isEmpty || !hasScanned {
                    Text("accounts.add.folders")
                        .font(DS.Typography.micro)
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(DS.Palette.textTertiary)
                    if !hasScanned {
                        HStack(spacing: DS.Spacing.xs) {
                            ProgressView().controlSize(.small).tint(DS.Palette.textSecondary)
                            Text("accounts.add.scanning")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textSecondary)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(candidates) { candidate in
                                folderButton(candidate)
                            }
                        }
                    }
                }

                HStack(spacing: DS.Spacing.md) {
                    Button(action: chooseFolder) {
                        Label(String(localized: "accounts.add.choose"), systemImage: "folder.badge.plus")
                    }
                    if isCustom {
                        Button {
                            apply(path: nil, service: nil)
                        } label: {
                            Label(String(localized: "accounts.mainFolder.reset"), systemImage: "arrow.uturn.backward")
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .disabled(applyingPath != nil)

                if let failure {
                    ConnectFailureView(result: failure)
                }

                Label {
                    Text("accounts.mainFolder.note")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)
        }
        .frame(width: 500)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.55))
        .onAppear(perform: scan)
        .onDisappear {
            scanTask?.cancel()
            applyTask?.cancel()
        }
    }

    private var currentFolder: some View {
        let path = accountsStore.mainRecord.configDir ?? ClaudeConfigDirResolver.defaultDirectory(home: home)
        return HStack(spacing: DS.Spacing.xs) {
            AccountDot(colorHex: accountsStore.mainRecord.colorHex, size: 10)
            Text(ClaudeConfigDirResolver.displayPath(path, home: home))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(isCustom
                 ? String(localized: "accounts.mainFolder.custom")
                 : String(localized: "accounts.mainFolder.default"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(DS.Palette.glassBorder, lineWidth: 1)
                )
        )
    }

    private func folderButton(_ candidate: ConfigDirCandidate) -> some View {
        Button {
            apply(path: candidate.path, service: candidate.matchedService)
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
                Text(candidate.displayPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: DS.Spacing.xs)
                if applyingPath == candidate.path {
                    ProgressView().controlSize(.small).tint(DS.Palette.textSecondary)
                } else {
                    Circle()
                        .fill(candidate.hasLogin ? DS.Palette.semanticSuccess : DS.Palette.semanticWarning)
                        .frame(width: 6, height: 6)
                    Text(candidate.hasLogin
                         ? String(localized: "accounts.mainFolder.hasLogin")
                         : String(localized: "accounts.add.status.none"))
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(Color.black.opacity(0.25))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(applyingPath != nil)
    }

    // MARK: - Actions

    private func scan() {
        scanTask?.cancel()
        let scanner = accountsStore.scanner
        let tracked = accountsStore.trackedPaths
        scanTask = Task {
            let found = await Task.detached(priority: .userInitiated) {
                scanner.candidates(excluding: tracked)
            }.value
            guard !Task.isCancelled else { return }
            candidates = found
            hasScanned = true
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: home, isDirectory: true)
        panel.prompt = String(localized: "accounts.add.choose.prompt")
        panel.message = String(localized: "accounts.mainFolder.choose.message")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        apply(path: url.path, service: nil)
    }

    private func apply(path: String?, service: String?) {
        applyTask?.cancel()
        applyingPath = path ?? ""
        failure = nil
        let proxy = settingsStore.proxyConfig
        applyTask = Task {
            let result = await accountsStore.setMainConfigDir(path, knownService: service, proxyConfig: proxy)
            guard !Task.isCancelled else { return }
            applyingPath = nil
            NSApp.activate(ignoringOtherApps: true)
            switch result {
            case .moved:
                isPresented = false
            case .refused(let reason):
                failure = reason
            }
        }
    }
}

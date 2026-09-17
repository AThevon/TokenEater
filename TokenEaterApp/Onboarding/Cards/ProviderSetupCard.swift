import SwiftUI

/// One provider, one card, whatever it takes to set that provider up.
///
/// Claude used to need two cards: `ClaudeCodeCard` in the providers row for
/// detection, and `ConnectCard` in the behaviour row for the Keychain prompt.
/// Codex had one. So Claude took twice the space, and half of its setup sat
/// under a heading about how the app behaves, which is what made Claude read
/// as the app itself and OpenAI as an addendum. Authorizing a credential is
/// not a behaviour; it is that provider's setup, and it belongs on that
/// provider's card.
///
/// Both providers now run the same five states through the same slots. The
/// content differs where the platforms genuinely differ (Claude's third state
/// raises a system dialog, OpenAI's asks you to run a command), but the card,
/// the order and the place to look are the same.
struct ProviderSetupCard: View {
    let provider: MetricProvider
    @ObservedObject var viewModel: OnboardingViewModel
    @EnvironmentObject private var settingsStore: SettingsStore

    private let accent = DS.Palette.brandPrimary

    var body: some View {
        OnboardingCard(
            tilt: provider == .claude ? .left : .right,
            title: provider.displayName,
            statusText: statusText,
            statusColor: statusColor,
            accent: accent,
            mark: {
                ProviderGlyph(provider: provider, size: 13)
                    .foregroundStyle(isTracked && state == .ready
                                     ? accent : DS.Palette.textSecondary)
            },
            badge: { OnboardingSourceLabel(text: sourceLabel) },
            scene: {
                scene
                    // Tracking off is a state of the whole card, not a line of
                    // text under it: the scene desaturates so a glance at the
                    // row says which providers are on.
                    .opacity(isTracked ? 1 : 0.42)
                    .saturation(isTracked ? 1 : 0.5)
            },
            control: { control }
        )
        .onAppear { refresh() }
        // The view model owns its own store (environment objects are not
        // reachable from a `@StateObject` initializer), so the switches have
        // to be mirrored back or progress would not move when one is flicked.
        .onChange(of: settingsStore.claudeEnabled) { _, _ in viewModel.syncTracking(from: settingsStore) }
        .onChange(of: settingsStore.codexEnabled) { _, _ in viewModel.syncTracking(from: settingsStore) }
    }

    // MARK: - State

    private var state: ProviderSetupState { viewModel.setupState(for: provider) }

    private var isTracked: Bool {
        provider == .claude ? settingsStore.claudeEnabled : settingsStore.codexEnabled
    }

    /// The last provider standing cannot be turned off. The store allows it so
    /// its own state stays simple; refusing it here is cheaper than an app
    /// with nothing left to show and an error explaining why.
    private var isLastTracked: Bool {
        isTracked && settingsStore.activeProviders.count < 2
    }

    private var trackingBinding: Binding<Bool> {
        provider == .claude ? $settingsStore.claudeEnabled : $settingsStore.codexEnabled
    }

    private var sourceLabel: String {
        String(localized: provider == .claude
               ? "onboarding.provider.claude.source"
               : "onboarding.provider.codex.source")
    }

    // MARK: - Scene

    @ViewBuilder
    private var scene: some View {
        switch state {
        case .checking:
            VStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("onboarding.provider.checking")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .notInstalled:
            installGuide
                .padding(10)

        case .needsAction:
            switch provider {
            case .claude: keyScene
            case .codex:  commandScene(command: "codex login",
                                       caption: "onboarding.provider.codex.signin.scene")
            }

        case .ready:
            switch provider {
            case .claude: terminalPreview.padding(10)
            case .codex:  loginScene.padding(10)
            }

        case .failed(let message):
            failureScene(message)
        }
    }

    /// Claude's third state. No fake macOS dialog: an icon and one line of
    /// brief, so the real system prompt is not a surprise.
    private var keyScene: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "key.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(accent)
                    .rotationEffect(.degrees(-15))
            }
            .shadow(color: accent.opacity(0.4), radius: 14)

            Text("onboarding.card.connect.idle.scene")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// OpenAI's third state. The work happens in a terminal, so the card shows
    /// the exact command rather than a button that cannot do it for you.
    private func commandScene(command: String, caption: LocalizedStringResource) -> some View {
        VStack(spacing: 10) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(red: 0.02, green: 0.03, blue: 0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
                .textSelection(.enabled)

            Text(caption)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terminalPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 7, height: 7)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 7, height: 7)
                Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: 7, height: 7)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.025))
            .overlay(
                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1),
                alignment: .bottom
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("~/proj").foregroundStyle(accent)
                    Text("$").foregroundStyle(.white.opacity(0.4))
                    Text("claude --version").foregroundStyle(.white)
                }
                Text("claude code 2.0.4").foregroundStyle(.white.opacity(0.55))
                Text("\u{2713} authorized").foregroundStyle(accent)
                HStack(spacing: 4) {
                    Text("~/proj").foregroundStyle(accent)
                    Text("$").foregroundStyle(.white.opacity(0.4))
                    BlinkingCursor(color: accent)
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(red: 0.02, green: 0.03, blue: 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var loginScene: some View {
        HStack(spacing: 11) {
            ProviderGlyph(provider: .codex, size: 22)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("codex.status.connected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(accountLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.white.opacity(0.12))
        )
    }

    private var accountLine: String {
        var parts: [String] = []
        let plan = viewModel.codexStatus.planType
        if plan != .unknown { parts.append(plan.displayLabel) }
        if case .chatgpt(_, _, let expiresAt) = viewModel.codexStatus, let expiresAt {
            parts.append(String(
                format: String(localized: "codex.status.validUntil"),
                expiresAt.formatted(date: .abbreviated, time: .omitted)
            ))
        }
        return parts.joined(separator: " · ")
    }

    private func failureScene(_ message: String) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(DS.Palette.semanticError.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Palette.semanticError)
            }
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var installGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(installSteps.enumerated()), id: \.offset) { index, key in
                HStack(alignment: .top, spacing: 7) {
                    Text("\(index + 1)")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.29))
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Color(red: 1.0, green: 0.62, blue: 0.04).opacity(0.18)))
                    Text(key)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var installSteps: [LocalizedStringResource] {
        switch provider {
        case .claude:
            return ["onboarding.card.claudecode.notfound.step1",
                    "onboarding.card.claudecode.notfound.step2",
                    "onboarding.card.claudecode.notfound.step3"]
        case .codex:
            return ["onboarding.provider.codex.notfound.step1",
                    "onboarding.provider.codex.notfound.step2",
                    "onboarding.provider.codex.notfound.step3"]
        }
    }

    // MARK: - Control

    /// The action, then the switch. The switch is present in every state on
    /// purpose: "I do not use this one" is an answer to the question this row
    /// asks, and a provider that is enabled but broken would otherwise be a
    /// step the user can neither complete nor drop.
    private var control: some View {
        HStack(spacing: 8) {
            actionButton
            Toggle("", isOn: trackingBinding)
                .toggleStyle(SwitchToggleStyle(tint: DS.Palette.brandPrimary))
                .controlSize(.mini)
                .labelsHidden()
                .disabled(isLastTracked)
                .opacity(isLastTracked ? 0.45 : 1)
                .help(isLastTracked ? String(localized: "onboarding.provider.lastOne") : "")
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state {
        case .checking, .ready:
            EmptyView()

        case .notInstalled:
            OnboardingActionButton(label: String(localized: "settings.redetect")) { refresh() }

        case .needsAction:
            switch provider {
            // The only state where the app can do the work itself: the button
            // raises the real Keychain prompt. OpenAI's equivalent happens in
            // a terminal, so its card shows the command and re-reads after.
            case .claude:
                OnboardingActionButton(
                    label: String(localized: "onboarding.card.connect.authorize"),
                    isProminent: true
                ) { viewModel.connect() }
            case .codex:
                OnboardingActionButton(label: String(localized: "settings.redetect")) { refresh() }
            }

        case .failed:
            OnboardingActionButton(label: String(localized: "settings.redetect")) {
                if provider == .claude { viewModel.connectionStatus = .idle }
                refresh()
            }
        }
    }

    // MARK: - Status line

    private var statusText: String {
        if state == .ready, !isTracked { return String(localized: "onboarding.provider.trackingOff") }
        switch state {
        case .checking:
            return String(localized: "onboarding.card.claudecode.status.checking")
        case .notInstalled:
            return provider == .claude
                ? String(localized: "onboarding.card.claudecode.status.notfound")
                : String(localized: "codex.status.notInstalled")
        case .needsAction:
            switch provider {
            case .claude:
                return String(localized: "onboarding.card.connect.status.idle")
            case .codex:
                return viewModel.codexStatus == .apiKeyOnly
                    ? String(localized: "codex.status.apiKey")
                    : String(localized: "codex.status.noCredentials")
            }
        case .ready:
            return provider == .claude
                ? String(localized: "onboarding.provider.claude.status.ready")
                : String(localized: "codex.status.connected")
        case .failed:
            return provider == .claude
                ? String(localized: "onboarding.card.connect.status.failed")
                : String(localized: "codex.status.expired")
        }
    }

    private var statusColor: Color {
        if state == .ready, !isTracked { return .white.opacity(0.3) }
        switch state {
        case .checking:     return .white.opacity(0.3)
        case .notInstalled: return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .needsAction:  return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .ready:        return accent
        case .failed:       return DS.Palette.semanticError
        }
    }

    // MARK: - Actions

    private func refresh() {
        switch provider {
        case .claude: viewModel.checkClaudeCode()
        case .codex:  viewModel.checkCodex()
        }
        viewModel.syncTracking(from: settingsStore)
    }
}

/// Terminal cursor that blinks via on/off opacity. Pulled out so the terminal
/// preview stays declarative.
private struct BlinkingCursor: View {
    let color: Color
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 4, height: 9)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

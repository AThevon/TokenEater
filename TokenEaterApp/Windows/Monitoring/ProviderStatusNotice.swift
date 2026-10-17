import SwiftUI

/// The one place the dashboard admits that a provider is not answering.
///
/// It used to live inside the Codex section, which the composable dashboard
/// replaced. Blocks render numbers, so an expired token drew a hero at 0%
/// with a cheerful empty grid under it and said nothing at all. A state
/// banner is not a block either: it belongs to no layout, Studio cannot hide
/// it, and it renders above the blocks in every mode.
///
/// Symmetric across providers because the two stores expose the same
/// `AppErrorState`. The two Codex-only rows below it are genuinely
/// Codex-only: OpenAI reports its windows dynamically, so "connected but no
/// window" and "limit reached" are states Claude's fixed 5h/7d pair cannot
/// be in.
struct ProviderStatusNotice: View {
    let provider: MetricProvider

    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var codexStore: CodexUsageStore

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                if let errorMessage {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(errorMessage)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(DS.Typography.label)
                    .foregroundStyle(.orange)
                    CopyDiagnosticButton()
                }
                if showsLimitReached {
                    Label(String(localized: "codex.limitReached"), systemImage: "exclamationmark.circle.fill")
                        .font(DS.Typography.label)
                        .foregroundStyle(.red)
                }
                if showsNoWindows {
                    Text("codex.test.noWindows")
                        .font(DS.Typography.label)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hasContent: Bool {
        Self.hasContent(provider: provider, usageStore: usageStore, codexStore: codexStore)
    }

    private var errorMessage: String? {
        Self.errorMessage(provider: provider, usageStore: usageStore, codexStore: codexStore)
    }

    private var showsLimitReached: Bool {
        Self.showsLimitReached(provider: provider, codexStore: codexStore)
    }

    private var showsNoWindows: Bool {
        Self.showsNoWindows(provider: provider, codexStore: codexStore)
    }

    /// Whether the notice draws anything, so the dashboard can leave its row
    /// out when no column of the row has one.
    @MainActor
    static func hasContent(provider: MetricProvider, usageStore: UsageStore, codexStore: CodexUsageStore) -> Bool {
        errorMessage(provider: provider, usageStore: usageStore, codexStore: codexStore) != nil
            || showsLimitReached(provider: provider, codexStore: codexStore)
            || showsNoWindows(provider: provider, codexStore: codexStore)
    }

    /// Nil while the provider is fine, and nil as well for the calm case
    /// where the token is momentarily unreadable but a snapshot is still on
    /// screen: the app recovers from that by itself, and an alarm the user
    /// cannot act on is worse than no alarm. An hour after the login expired
    /// it no longer recovers by itself, and the notice says what to do (#268).
    @MainActor
    private static func errorMessage(provider: MetricProvider, usageStore: UsageStore, codexStore: CodexUsageStore) -> String? {
        switch provider {
        case .claude:
            if usageStore.errorState == .tokenUnavailable, let since = usageStore.loginExpiredSince {
                let headline = String(format: String(localized: "error.login.expired"),
                                      since.formatted(.relative(presentation: .named)))
                return headline + ". " + usageStore.loginExpiredHint
            }
            guard !usageStore.isAwaitingRefresh else { return nil }
            switch usageStore.errorState {
            case .tokenUnavailable:
                return usageStore.authFailureHint ?? String(localized: "error.banner.reauth.hint")
            case .rateLimited:      return String(localized: "error.banner.apiunavailable")
            case .networkError:     return String(localized: "error.network.generic")
            case .none:             return nil
            }
        case .codex:
            guard !codexStore.isAwaitingRefresh else { return nil }
            switch codexStore.errorState {
            case .tokenUnavailable: return codexStore.connectionStatus
            case .rateLimited:      return String(localized: "codex.error.rateLimited")
            case .networkError:     return String(localized: "error.network.generic")
            case .none:             return nil
            }
        }
    }

    @MainActor
    private static func showsLimitReached(provider: MetricProvider, codexStore: CodexUsageStore) -> Bool {
        provider == .codex && codexStore.limitReached
    }

    @MainActor
    private static func showsNoWindows(provider: MetricProvider, codexStore: CodexUsageStore) -> Bool {
        provider == .codex
            && codexStore.windows.isEmpty
            && !codexStore.hasError
            && !codexStore.isLoading
    }
}

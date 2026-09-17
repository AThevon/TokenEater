import SwiftUI

/// Codex's hero, sized and dressed exactly like Claude's so the two sit as
/// peers in the glance band.
///
/// It shows the window closest to its cap rather than always the session one:
/// Codex plans do not all have a 5-hour window, and on a weekly-only plan the
/// session slot would otherwise be permanently empty.
///
/// The face itself comes from `ProviderHeroFace`, the same one Claude wears.
/// It used to be a separate approximation and the two drifted where it shows
/// most, side by side in the glance band: different type scale on the big
/// number, a lowercase reset line against an uppercase tracked one, a smaller
/// ring with no pacing glyph.
///
/// No flip yet, deliberately. Claude's back face shows a usage trajectory and
/// a live column built from `sessionSamples`, which is Claude-only data the
/// Codex pipeline does not produce. Faking that face would be worse than not
/// having it; the card is the same size and weight either way, which is what
/// the symmetry actually rests on.
struct CodexHeroCard: View {
    @EnvironmentObject private var codexStore: CodexUsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var hovering = false

    /// The shortest window the plan actually has, unless the user pinned one.
    ///
    /// This used to be "whichever window is closest to its cap", which made
    /// this card answer a different question from Claude's: that one is
    /// pinned to the 5-hour window, the one that blocks you in the next ten
    /// minutes. Same rule on both sides now, and the fallback still covers
    /// the case the old rule existed for, a Pro plan with no 5-hour window at
    /// all, because shortest-available then simply means weekly.
    private var window: CodexWindowSnapshot? {
        if let pinned = settingsStore.heroWindow(for: .codex),
           let match = codexStore.windows.first(where: { $0.kind.rawValue == pinned }) {
            return match
        }
        return codexStore.windows.min { $0.windowDuration < $1.windowDuration }
    }

    /// A reset instant already in the past is not a countdown. Claude's card
    /// shows its placeholder in that case; this one did too, before the face
    /// was shared, and it has to keep doing it.
    private var isResetPending: Bool {
        guard let reset = window?.resetDate else { return false }
        return reset > Date()
    }

    var body: some View {
        let pct = window?.pct ?? 0
        let mode = GaugeColorResolver.mode(
            smartColorEnabled: settingsStore.smartColorEnabled,
            windowDuration: window?.windowDuration ?? 0
        )
        let accent = GaugeColorResolver.color(
            mode: mode,
            utilization: pct,
            resetDate: window?.resetDate,
            windowDuration: window?.windowDuration ?? 0,
            theme: themeStore.current,
            thresholds: themeStore.thresholds,
            pacingMargin: Double(settingsStore.pacingMargin),
            now: Date(),
            profile: settingsStore.smartColorProfile
        )
        let gradient = GaugeColorResolver.gradient(
            mode: mode,
            utilization: pct,
            resetDate: window?.resetDate,
            windowDuration: window?.windowDuration ?? 0,
            theme: themeStore.current,
            thresholds: themeStore.thresholds,
            pacingMargin: Double(settingsStore.pacingMargin),
            now: Date(),
            profile: settingsStore.smartColorProfile,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return ProviderHeroFace(
            provider: .codex,
            windowLabel: window.map { $0.kind.heroLabel(for: $0.windowDuration) }
                ?? String(localized: "codex.hero.noWindow"),
            pct: pct,
            gaugeColor: accent,
            gaugeGradient: gradient,
            zone: window?.pacing?.zone,
            resetText: isResetPending ? (window?.relativeReset ?? "") : "",
            resetDate: isResetPending ? window?.resetDate : nil
        )
        .padding(DS.Spacing.lg)
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                // No `.ultraThinMaterial` here, deliberately, and it is not an
                // oversight to fix. These two cards are the only ones in the
                // app whose width animates, and a material re-blurs its
                // backdrop on every frame of that resize, which is what made
                // a mode switch feel like it was stuttering. It was also
                // buying nothing: what sits behind is `dsWindowBackground`, a
                // two-stop linear gradient, and a blurred linear gradient is
                // the same linear gradient. The 15% the fill lets through now
                // shows that gradient directly instead of a costly copy of it.
                RoundedRectangle(cornerRadius: DS.Radius.cardLg)
                    .fill(DS.Palette.bgElevated.opacity(0.85))
                RoundedRectangle(cornerRadius: DS.Radius.cardLg)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(hovering ? 0.10 : 0.05), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.cardLg)
                .stroke(accent.opacity(hovering ? 0.40 : 0.18), lineWidth: 1)
        )
        .dsShadow(hovering ? DS.Shadow.lift : DS.Shadow.subtle)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("OpenAI Codex \(window?.label ?? "") \(pct)%"))
    }
}

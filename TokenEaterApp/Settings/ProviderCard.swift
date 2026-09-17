import SwiftUI

/// One provider, one card.
///
/// Both providers used to share a card: two rows, then a Test button that
/// looked like it belonged to the row above it, then a Copy diagnostic button
/// that belongs to neither, then a second card repeating Claude's status in
/// different words. Nothing owned anything.
///
/// Each card owns its mark, its state, its account, its own action and its own
/// switch, and the app-level action moved out to the section footer where it
/// belongs. Turning a provider off collapses its body rather than leaving a
/// live-looking card with a dead toggle: the shape says what is on before you
/// read a word.
struct ProviderCard<Action: View>: View {
    let provider: MetricProvider
    let name: String
    let isEnabled: Bool
    let isLive: Bool
    /// The connection sentence, " · " separated. The first part is the state,
    /// the rest are facts about the account.
    let status: String
    /// Non-empty disables the switch and says why, for the last provider on.
    var lockedReason: String = ""
    @Binding var enabled: Bool
    @ViewBuilder var action: () -> Action

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var parts: [String] {
        status.components(separatedBy: " · ").filter { !$0.isEmpty }
    }
    private var lead: String { parts.first ?? status }
    private var chips: [String] { Array(parts.dropFirst()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isEnabled {
                body(for: provider)
                    .transition(.opacity)
            }
        }
        .padding(DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color.white.opacity(isEnabled ? 0.045 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(
                    isLive ? DS.Palette.brandPrimary.opacity(hovering ? 0.34 : 0.22)
                           : Color.white.opacity(hovering ? 0.14 : 0.07),
                    lineWidth: 1
                )
        )
        // Desktop: opacity only, 100ms, nothing that moves. This sits on
        // screen while someone reads the rest of the page.
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: hovering)
        .animation(reduceMotion ? nil : DS.Motion.glide, value: isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(isLive ? DS.Palette.brandPrimary.opacity(0.14) : Color.white.opacity(0.05))
                    .frame(width: 26, height: 26)
                ProviderGlyph(provider: provider, size: 14)
                    .foregroundStyle(isLive ? DS.Palette.brandPrimary : DS.Palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(isEnabled ? lead : String(localized: "settings.providers.off"))
                    .font(.system(size: 11))
                    .foregroundStyle(isLive ? DS.Palette.brandPrimary.opacity(0.9) : DS.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: DS.Spacing.xs)

            Toggle("", isOn: $enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.8)
                .disabled(!lockedReason.isEmpty)
                .opacity(lockedReason.isEmpty ? 1 : 0.45)
                .help(lockedReason)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func body(for provider: MetricProvider) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Chips and the action share one line. They were stacked, which
            // cost a whole row of height per card for a row that was mostly
            // empty on both sides.
            HStack(alignment: .center, spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.white.opacity(0.06))
                                .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))
                        )
                }
                Spacer(minLength: DS.Spacing.xs)
                action()
            }

            if !lockedReason.isEmpty {
                Text(lockedReason)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, DS.Spacing.xs)
        .padding(.leading, 34)
    }
}

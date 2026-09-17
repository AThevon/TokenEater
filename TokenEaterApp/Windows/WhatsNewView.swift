import SwiftUI

/// Shown once when the minor version changes, in the dashboard window, in the
/// slot the wizard uses on a fresh install.
///
/// Three panes, and only the first one is new work: the second hosts the real
/// `ProviderModeSwitcher` and the third the real Codex connect card, because a
/// screenshot of a control teaches nothing you can act on.
struct WhatsNewView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pane = 0
    private let panes = 2

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            brandBar

            // The merged step carries the selector, its caption and the full
            // Providers card, which can outgrow a short window. Scrolls only
            // when it has to, so the usual case still reads as a fixed pane.
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch pane {
                    case 0: coveragePane
                    default: setupPane
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .padding(.top, DS.Spacing.lg)

            // A fixed gap under the header with the footer pinned, rather than
            // centring: the three panes are different heights, and centring
            // made the title jump vertically on every Next.
            Spacer(minLength: DS.Spacing.lg)

            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 18)
        // One measure for everything: the subtitle stays near 65 characters
        // and the matrix rows stop stretching their two ends apart.
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chrome

    private var brandBar: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text("TokenEater \(SettingsStore.currentVersion)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer()
            Button(action: finish) {
                Text("whatsNew.skip")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Spacing.sm) {
            HStack(spacing: 6) {
                ForEach(0..<panes, id: \.self) { index in
                    Capsule()
                        .fill(index == pane ? DS.Palette.textPrimary.opacity(0.8) : Color.white.opacity(0.16))
                        .frame(width: index == pane ? 16 : 6, height: 6)
                        .animation(reduceMotion ? nil : DS.Motion.springSnap, value: pane)
                }
            }
            Spacer()
            if pane > 0 {
                secondaryButton("whatsNew.back") { pane -= 1 }
            }
            primaryButton(pane == panes - 1 ? "whatsNew.done" : "whatsNew.next") {
                if pane == panes - 1 { finish() } else { pane += 1 }
            }
        }
    }

    // MARK: - Panes

    private var coveragePane: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            title("whatsNew.coverage.title", "whatsNew.coverage.body")
            // `animated` is what makes the gap legible: rows cascade and a
            // capability only one provider carries holds a beat before its
            // second mark fails to land.
            CoverageMatrixView(animated: true, showsHeading: false)
                .id(pane)
        }
    }

    /// The selector and the toggles that decide whether it exists, on one
    /// step, in that order.
    ///
    /// Separate steps made the second one contradict the first: turning a
    /// provider off there emptied the selector you had just been shown, and
    /// you had to walk back to see it. Together, the toggles are the demo -
    /// flip the second provider on and the selector appears above them.
    private var setupPane: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            title("whatsNew.mode.title", "whatsNew.mode.body")

            HStack {
                Spacer()
                if settingsStore.availableProviderModes.count > 1 {
                    ProviderModeSwitcher(size: .regular, showsCaption: true)
                } else {
                    singleProviderNotice
                }
                Spacer()
            }
            .padding(.vertical, DS.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .fill(DS.Palette.bgElevated.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card)
                            .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
                    )
            )
            .animation(reduceMotion ? nil : DS.Motion.easeOut,
                       value: settingsStore.availableProviderModes.count)

            Text("whatsNew.mode.hint")
                .font(.system(size: 11))
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("whatsNew.connect.title")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("whatsNew.connect.body")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, DS.Spacing.xs)

            ProvidersSectionProviders()
        }
    }

    private var singleProviderNotice: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                ForEach(settingsStore.activeProviders) { provider in
                    ProviderGlyph(provider: provider, size: 15)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            Text(String(
                format: String(localized: "whatsNew.mode.single"),
                settingsStore.activeProviders.first?.displayName ?? ""
            ))
            .font(.system(size: 12))
            .foregroundStyle(DS.Palette.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Pieces

    private func title(_ heading: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading)
                .font(DS.Typography.title1)
                .foregroundStyle(DS.Palette.textPrimary)
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func primaryButton(_ key: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.bgElevated)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(DS.Palette.textPrimary.opacity(0.92)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }

    private func secondaryButton(_ key: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(key)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func finish() {
        settingsStore.markWhatsNewSeen()
    }
}

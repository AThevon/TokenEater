import SwiftUI

// MARK: - Studio pill anchor

/// Reports the Studio pill's frame from `TopPillsNav` up to `MainAppView`,
/// where the discovery bubble anchors itself under the pill.
struct StudioPillAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

// MARK: - Discovery bubble

/// One-shot bubble pointing at the new Studio pill after an upgrade. Shown
/// until the user opens the Studio, opens the what's-new sheet, or dismisses
/// it; never shown to fresh installs (see `SettingsStore.hasSeenStudioIntro`).
struct StudioIntroBubble: View {
    /// X position of the arrow tip, in the bubble's own coordinate space.
    let arrowX: CGFloat
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Triangle()
                .fill(DS.Palette.bgOverlay)
                .frame(width: 14, height: 7)
                .overlay(Triangle().stroke(DS.Palette.accentStudio.opacity(0.45), lineWidth: 1))
                .offset(x: arrowX - 7)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.accentStudio)
                    Text(String(localized: "studio.intro.badge"))
                        .font(DS.Typography.micro)
                        .tracking(1.2)
                        .foregroundStyle(DS.Palette.accentStudio)

                    Spacer(minLength: DS.Spacing.sm)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DS.Palette.textTertiary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text(String(localized: "studio.intro.text"))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onOpen) {
                    Text(String(localized: "studio.intro.cta"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(DS.Palette.accentStudio.opacity(0.22))
                                .overlay(Capsule().stroke(DS.Palette.accentStudio.opacity(0.5), lineWidth: 1))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous)
                    .fill(DS.Palette.bgOverlay)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous)
                            .stroke(DS.Palette.accentStudio.opacity(0.45), lineWidth: 1)
                    )
            )
            .dsGlow(color: DS.Palette.accentStudio, token: DS.Glow.subtle)
            .dsShadow(DS.Shadow.lift)
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - What's new sheet

/// Post-update highlights: the Studio and the composable surfaces. Presented
/// once from the discovery bubble; every exit marks the intro as seen.
struct WhatsNewSheet: View {
    let onOpenStudio: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(DS.Palette.accentStudio)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(DS.Palette.accentStudio.opacity(0.14))
                            .overlay(Circle().stroke(DS.Palette.accentStudio.opacity(0.35), lineWidth: 1))
                    )
                    .dsGlow(color: DS.Palette.accentStudio, token: DS.Glow.subtle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "whatsnew.title"))
                        .font(DS.Typography.title2)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(String(localized: "whatsnew.subtitle"))
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                row(icon: "wand.and.stars",
                    title: "whatsnew.studio.title",
                    text: "whatsnew.studio.text")
                row(icon: "menubar.dock.rectangle",
                    title: "whatsnew.popover.title",
                    text: "whatsnew.popover.text")
                row(icon: "menubar.rectangle",
                    title: "whatsnew.menubar.title",
                    text: "whatsnew.menubar.text")
                row(icon: "square.grid.2x2",
                    title: "whatsnew.templates.title",
                    text: "whatsnew.templates.text")
            }

            HStack {
                Button(action: onLater) {
                    Text(String(localized: "whatsnew.later"))
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onOpenStudio) {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(String(localized: "whatsnew.open"))
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(DS.Palette.accentStudio.opacity(0.24))
                            .overlay(Capsule().stroke(DS.Palette.accentStudio.opacity(0.55), lineWidth: 1))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .dsGlow(color: DS.Palette.accentStudio, token: DS.Glow.subtle)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Spacing.xl)
        .frame(width: 440)
        .environment(\.colorScheme, .dark)
        .presentationBackground(DS.Palette.bgElevated)
    }

    private func row(
        icon: String,
        title: String.LocalizationValue,
        text: String.LocalizationValue
    ) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Palette.accentStudio)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.Palette.accentStudio.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                .stroke(DS.Palette.accentStudio.opacity(0.25), lineWidth: 1)
                        )
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: title))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(String(localized: text))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

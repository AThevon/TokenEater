import SwiftUI
import AppKit

/// Top strip of the Studio space -> one card per customizable surface, each
/// carrying a live miniature of that surface. Clicking a card switches the
/// editor below; the active card glows with the Studio accent.
struct StudioSurfaceSwitcher: View {
    @Binding var selection: StudioSection

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(StudioSection.allCases, id: \.rawValue) { surface in
                StudioSurfaceCard(surface: surface, isActive: surface == selection) {
                    guard selection != surface else { return }
                    withAnimation(DS.Motion.springSnap) {
                        selection = surface
                    }
                }
            }
        }
    }
}

// MARK: - Card

private struct StudioSurfaceCard: View {
    let surface: StudioSection
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: surface.iconName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isActive ? DS.Palette.accentStudio : DS.Palette.textTertiary)
                        Text(surface.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isActive ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                            .lineLimit(1)
                    }
                    Text(surface.hint)
                        .font(DS.Typography.micro)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: DS.Spacing.xs)

                preview
                    .frame(width: 112, height: 64)
                    .allowsHitTesting(false)
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous)
                    .fill(DS.Palette.bgElevated.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .dsGlow(color: isActive ? DS.Palette.accentStudio : .clear, token: DS.Glow.subtle)
            .scaleEffect(isHovering && !isActive ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.springSnap) { isHovering = hovering }
        }
    }

    private var fillOpacity: Double {
        if isActive { return 0.92 }
        if isHovering { return 0.72 }
        return 0.55
    }

    private var borderColor: Color {
        if isActive { return DS.Palette.accentStudio.opacity(0.55) }
        if isHovering { return DS.Palette.glassBorder }
        return DS.Palette.glassBorderLo
    }

    @ViewBuilder
    private var preview: some View {
        switch surface {
        case .popover: StudioPopoverThumbnail()
        case .menuBar: StudioMenuBarThumbnail()
        case .themes:  StudioThemesThumbnail()
        }
    }
}

// MARK: - Live thumbnails

/// Miniature of the real popover -> renders the production view scaled down,
/// clipped to the card and faded out at the bottom. Non-interactive.
private struct StudioPopoverThumbnail: View {
    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                MenuBarPopoverView()
                    .fixedSize()
                    .scaleEffect(0.36, anchor: .top)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.6),
                        .init(color: .white.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// Miniature of the menu bar item -> same pixels as the status bar, rendered
/// through the shared `RenderData.live` path, on a simulated dark menu bar.
private struct StudioMenuBarThumbnail: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var vendorStatusStore: VendorStatusStore

    var body: some View {
        let data = MenuBarRenderer.RenderData.live(
            usage: usageStore,
            theme: themeStore,
            settings: settingsStore,
            vendor: vendorStatusStore
        )
        let image = MenuBarRenderer.renderWithHitRects(data).image
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: NSColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
                .frame(height: 30)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 96, maxHeight: 18)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Swatch strip of the active theme -> gauge colors as overlapping dots,
/// pacing colors as a small capsule row underneath.
private struct StudioThemesThumbnail: View {
    @EnvironmentObject private var themeStore: ThemeStore

    var body: some View {
        let theme = themeStore.current
        return VStack(spacing: DS.Spacing.xs) {
            HStack(spacing: -7) {
                swatch(theme.gaugeNormal)
                swatch(theme.gaugeWarning)
                swatch(theme.gaugeCritical)
            }
            HStack(spacing: 4) {
                pacingChip(theme.pacingChill)
                pacingChip(theme.pacingOnTrack)
                pacingChip(theme.pacingWarning)
                pacingChip(theme.pacingHot)
            }
        }
    }

    private func swatch(_ hex: String) -> some View {
        Circle()
            .fill(Color(hex: hex))
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 1.5))
    }

    private func pacingChip(_ hex: String) -> some View {
        Capsule()
            .fill(Color(hex: hex))
            .frame(width: 13, height: 5)
    }
}

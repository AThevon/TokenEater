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
        // Same card language as the Monitoring tiles: panel fill + material,
        // a faint accent wash, an accent-tinted hairline that strengthens on
        // active / hover, and a plain depth shadow. No coloured glow halo, so
        // the Studio reads as the same app as the Stats page.
        let accent = DS.Palette.accentStudio
        let strokeOpacity = isActive ? 0.45 : (isHovering ? 0.30 : 0.12)
        let washOpacity = isActive ? 0.12 : (isHovering ? 0.07 : 0.04)

        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: surface.iconName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isActive ? accent : DS.Palette.textTertiary)
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
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.Palette.bgPanel.opacity(0.92))
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(LinearGradient(colors: [accent.opacity(washOpacity), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(accent.opacity(strokeOpacity), lineWidth: 1)
            )
            .dsShadow(isActive || isHovering ? DS.Shadow.lift : DS.Shadow.subtle)
        }
        .buttonStyle(CardPressStyle(isHovered: isHovering, accent: accent, cornerRadius: DS.Radius.card))
        .onHover { hovering in
            withAnimation(DS.Motion.springSnap) { isHovering = hovering }
        }
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
        // Same RenderData as the real status item -> `render(_:)` is the
        // memoized path shared with StatusBarController, so this is a cache
        // hit almost every time instead of a fresh synchronous raster, and
        // it shows the outage badge faithfully.
        let image = MenuBarRenderer.render(data)
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

import SwiftUI

/// Top pills navigation -> 3 segmented pills with a glow highlight that glides
/// from one pill to the next via `matchedGeometryEffect`. The highlight tints
/// itself with the destination module's accent color, so switching from
/// `Stats` (green) to `History` (blue) reads as a fluid color hand-off rather
/// than a discrete tab change.
///
/// Hover on inactive pills fades the label from tertiary to secondary and
/// applies a 1.04 scale via spring-snap; the active pill carries a soft halo
/// (radial shadow) in its accent color. `reduceMotion` swaps the matched
/// geometry for a plain opacity crossfade.
struct TopPillsNav: View {
    @Binding var selection: AppSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pillNamespace
    @State private var hoveredPill: AppSpace? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(AppSpace.allCases, id: \.rawValue) { space in
                pill(for: space)
            }
        }
        .padding(DS.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous)
                .fill(DS.Palette.bgElevated.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous)
                        .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func pill(for space: AppSpace) -> some View {
        let isActive = space == selection
        let isHovered = hoveredPill == space
        let accent = accent(for: space)

        Button {
            guard !isActive else { return }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : DS.Motion.springSnap) {
                selection = space
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: space.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                // Render the label with a stable layout: we always reserve the
                // "semibold" footprint by overlaying a hidden semibold ghost,
                // and only swap the visible weight via opacity. Without this,
                // toggling weight between regular and semibold would resize
                // the text and shift the whole nav box.
                Text(space.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(foreground(isActive: isActive, isHovered: isHovered))
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 7)
            // Intrinsic width per pill (no shared frame). The total nav width
            // stays constant because all three pills keep their natural size
            // regardless of which one is active -> matchedGeometryEffect glide
            // runs between fixed positions, no shift.
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
            .background(
                ZStack {
                    if isActive {
                        if reduceMotion {
                            // No geometry hand-off when motion reduced.
                            highlight(accent: accent)
                                .transition(.opacity)
                        } else {
                            highlight(accent: accent)
                                .matchedGeometryEffect(id: "active-pill", in: pillNamespace)
                        }
                    }
                }
            )
            // Hover lift only on inactive pills; active stays neutral so the
            // moving highlight isn't fighting another transform.
            .scaleEffect(isHovered && !isActive ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DS.Motion.springSnap) {
                if hovering {
                    hoveredPill = space
                } else if hoveredPill == space {
                    hoveredPill = nil
                }
            }
        }
    }

    /// Highlight surface for the active pill. Tinted with the destination
    /// accent (green / blue / orange), with an outer halo via shadow.
    private func highlight(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent.opacity(0.28), accent.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                    .stroke(accent.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: accent.opacity(0.40), radius: 12, x: 0, y: 0)
            .shadow(color: accent.opacity(0.20), radius: 24, x: 0, y: 0)
    }

    private func accent(for space: AppSpace) -> Color {
        switch space {
        case .monitoring: DS.Palette.accentStats
        case .history:  DS.Palette.accentHistory
        case .settings: DS.Palette.accentSettings
        }
    }

    private func foreground(isActive: Bool, isHovered: Bool) -> Color {
        if isActive { return DS.Palette.textPrimary }
        if isHovered { return DS.Palette.textSecondary }
        return DS.Palette.textTertiary
    }
}

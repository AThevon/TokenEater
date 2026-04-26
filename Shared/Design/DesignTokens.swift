import SwiftUI
import AppKit

/// TokenEater design tokens -> single source of truth for the window app chrome
/// (sidebar, cards, panels, typo, spacing, motion).
///
/// Scope : window app only. Does NOT apply to the menu bar, popover, or widget,
/// which keep their existing identity.
///
/// Cohabits with user themes (`ThemeColors` + presets default/neon/pastel/monochrome)
/// which continue to color *only* the data points (gauges, pacing dots, metric
/// values). The chrome stays constant regardless of the active theme.
///
/// Reference -> `docs/design/MASTER.md`
enum DS {

    // MARK: - Palette (Chrome)

    enum Palette {
        // Three-tier depth hierarchy. All R=G=B for a strictly neutral grey
        // ramp -> no blue / warm tint, just luminance steps.
        // L0 (window) -> bgBase.
        // L1 (outer panels: Settings content + SubSidebar siblings, Stats Hero, pacing, settings.* sections) -> bgElevated.
        // L2 (innermost: nested metric tiles inside grids) -> bgPanel.
        static let bgBase     = Color(hex: "#0E0E0E") // L0
        static let bgElevated = Color(hex: "#141414") // L1
        static let bgPanel    = Color(hex: "#1A1A1A") // L2
        static let bgOverlay  = Color(hex: "#1C1C1C")
        static let bgHover    = Color(hex: "#202020")
        static let bgActive   = Color(hex: "#242424")

        // Ambient gradient -> top-left lift (L1) -> bottom-right floor (L0)
        static let gradientTopLeft     = Color(hex: "#141414")
        static let gradientBottomRight = Color(hex: "#0E0E0E")

        // Glass
        static let glassFill     = Color.white.opacity(0.03)
        static let glassFillHi   = Color.white.opacity(0.06)
        static let glassBorder   = Color.white.opacity(0.08) // bumped from 0.06 for clearer panel edges
        static let glassBorderHi = Color.white.opacity(0.14)
        static let glassBorderLo = Color.white.opacity(0.04)

        // Text -> exact site values
        static let textPrimary   = Color(hex: "#F5F5F7")
        static let textSecondary = Color(hex: "#A1A1AA")
        static let textTertiary  = Color(hex: "#63636E")
        static let textDisabled  = Color(hex: "#63636E").opacity(0.4)

        // Module accents -> three hues already native to the site.
        // Stats = lime green (brand primary), History = info blue,
        // Settings = warm orange. Opacity capped at 0.15 when used as fill.
        static let accentStats    = Color(hex: "#32CE6A") // brand green -> data, confidence
        static let accentHistory  = Color(hex: "#60A5FA") // info blue -> time, narrative
        static let accentSettings = Color(hex: "#FFB347") // warm orange -> config, control

        // Brand green variants (for pressed / light states on primary actions)
        static let brandPrimary  = Color(hex: "#32CE6A")
        static let brandPressed  = Color(hex: "#28A554")
        static let brandLight    = Color(hex: "#5EDDA0")

        // Semantic states (notifications, banners, errors).
        // Re-use site tokens so the app feels consistent with the landing page.
        static let semanticSuccess = Color(hex: "#32CE6A")
        static let semanticWarning = Color(hex: "#FFB347")
        static let semanticError   = Color(hex: "#F87171")
        static let semanticInfo    = Color(hex: "#60A5FA")
    }

    // MARK: - Spacing

    /// Base 4pt, multiplicative scale. A card uses a single internal padding
    /// level (`.md` by default); sub-groups breathe with `.xs`/`.sm`.
    enum Spacing {
        static let xxs:  CGFloat = 4
        static let xs:   CGFloat = 8
        static let sm:   CGFloat = 12
        static let md:   CGFloat = 16
        static let lg:   CGFloat = 24
        static let xl:   CGFloat = 32
        static let xxl:  CGFloat = 48
        static let xxxl: CGFloat = 64
    }

    // MARK: - Radii

    /// Rule : larger surface -> larger radius. Tightened from the original
    /// soft-glass scale -> pulled values down to read more crisp / less
    /// "pill-y" without going full sharp-edged.
    enum Radius {
        static let input:  CGFloat = 6
        static let small:  CGFloat = 6
        static let card:   CGFloat = 8
        static let cardLg: CGFloat = 12
        static let modal:  CGFloat = 16
        static let pill:   CGFloat = 100
    }

    // MARK: - Layout

    /// Hard-coded layout dimensions for top-level windows / panels.
    /// Centralised so the onboarding (and future panels) read from a single
    /// source instead of magic numbers in `MainAppView`.
    enum Layout {
        /// Onboarding window - 16:10 macbook-style ratio. Sized to feel
        /// present on a MacBook display without going fullscreen. The user
        /// passes through this once at first launch (and again if they
        /// reset onboarding from Settings). Designed to fit a 2x2 cards
        /// grid next to a left-side hero column.
        static let onboardingWindow = CGSize(width: 1080, height: 675)
    }

    // MARK: - Shadows

    /// Shadow token -> deep but soft, glass-compatible.
    /// Low alpha + large blur so shadows never look hard on dark chrome.
    struct ShadowToken {
        let radius: CGFloat
        let y: CGFloat
        let alpha: Double

        var color: Color { Color.black.opacity(alpha) }
    }

    enum Shadow {
        static let flat   = ShadowToken(radius: 0,  y: 0,  alpha: 0)
        static let subtle = ShadowToken(radius: 12, y: 4,  alpha: 0.12)
        static let lift   = ShadowToken(radius: 24, y: 8,  alpha: 0.20)
        static let elev   = ShadowToken(radius: 48, y: 16, alpha: 0.32)
    }

    /// Arc-like glow -> halo bleeding from the border on hover/focus.
    /// Apply via `.dsGlow(color:strong:)` below.
    enum Glow {
        static let subtle = ShadowToken(radius: 16, y: 0, alpha: 0.25)
        static let strong = ShadowToken(radius: 24, y: 0, alpha: 0.40)
    }

    // MARK: - Motion

    enum Duration {
        static let fast:  Double = 0.18   // micro hover, cursor changes
        static let base:  Double = 0.24   // default transitions
        static let slow:  Double = 0.40   // section changes, slide-ins
        static let xslow: Double = 0.60   // rare, hero entrances
    }

    enum Motion {
        // Standard easings
        static let easeOut   = Animation.easeOut(duration: Duration.base)
        static let easeIn    = Animation.easeIn(duration: Duration.base)
        static let easeInOut = Animation.easeInOut(duration: Duration.base)

        // Arc-like "liquid" springs
        static let springSnap   = Animation.spring(response: 0.30, dampingFraction: 0.90) // hover / press
        static let springLiquid = Animation.spring(response: 0.50, dampingFraction: 0.80) // section change
        static let springSoft   = Animation.spring(response: 0.70, dampingFraction: 0.85) // modal entry

        // Live metrics pulse (2s, never-ending, subtle)
        static let shimmerPulse = Animation
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
    }

    // MARK: - Typography

    /// Scale typographique. On s'appuie sur `.system` (SF Pro / SF Pro Display /
    /// SF Mono) pour zéro dépendance. Inter Display reste l'ambition long-terme
    /// mentionnée dans le MASTER.md -> on ship le font avec le bundle quand on
    /// veut le basculer, sans toucher aux call sites.
    enum Typography {
        static let display      = Font.system(size: 34, weight: .bold).leading(.tight)
        static let title1       = Font.system(size: 22, weight: .semibold)
        static let title2       = Font.system(size: 17, weight: .semibold)
        static let body         = Font.system(size: 13, weight: .regular)
        static let label        = Font.system(size: 11, weight: .medium)
        static let micro        = Font.system(size: 10, weight: .medium)
        static let metricLarge  = Font.system(size: 28, weight: .semibold, design: .monospaced)
        static let metricInline = Font.system(size: 13, weight: .regular, design: .monospaced)
    }
}

// MARK: - View modifiers

extension View {
    /// Apply a `DS.Shadow` / `DS.Glow` token directly.
    func dsShadow(_ token: DS.ShadowToken) -> some View {
        self.shadow(color: token.color, radius: token.radius, x: 0, y: token.y)
    }

    /// Tinted Arc-like glow using an arbitrary color (usually module accent).
    func dsGlow(color: Color, token: DS.ShadowToken = DS.Glow.subtle) -> some View {
        self.shadow(color: color.opacity(token.alpha), radius: token.radius, x: 0, y: token.y)
    }

    /// Standard glass surface : `bgElevated` at partial alpha, `.ultraThinMaterial`
    /// underneath for the blur, a soft inner border on top.
    func dsGlass(radius: CGFloat = DS.Radius.card) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(DS.Palette.bgElevated.opacity(0.72))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: radius)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(DS.Palette.glassBorder, lineWidth: 1)
            )
    }

    /// Full-bleed ambient gradient used as the window root background.
    func dsWindowBackground() -> some View {
        self.background(
            LinearGradient(
                colors: [DS.Palette.gradientTopLeft, DS.Palette.gradientBottomRight],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    /// Cursor-aware highlight ready for card hover. Pass a bound CGPoint
    /// updated via `.onContinuousHover`; the overlay draws a soft radial
    /// spotlight that follows the cursor, Arc-style.
    func dsSpotlight(at point: CGPoint?, tint: Color = .white) -> some View {
        self.overlay {
            GeometryReader { geo in
                if let p = point {
                    RadialGradient(
                        colors: [tint.opacity(0.08), .clear],
                        center: UnitPoint(
                            x: p.x / max(geo.size.width, 1),
                            y: p.y / max(geo.size.height, 1)
                        ),
                        startRadius: 0,
                        endRadius: 140
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

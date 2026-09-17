import SwiftUI

/// Shared chrome for the four onboarding cards. The scene (top) is custom
/// content; the meta (bottom) is a structured row of mark + title + badge,
/// then status + control. Tint is per-card; alternating tilt is applied via
/// the `tilt` parameter.
///
/// The badge slot used to be a REQUIRED / OPTIONAL stamp, which ranked the
/// cards against each other, and the providers with them. The wizard's own
/// Finish gate has always accepted either provider on its own, so the stamp
/// contradicted the code. The slot now carries what the card actually has to
/// say: where a provider's credentials come from, or which providers a
/// feature covers.
struct OnboardingCard<Mark: View, Badge: View, Scene: View, Control: View>: View {
    enum Tilt { case left, right }

    let tilt: Tilt
    let title: String
    let statusText: String
    let statusColor: Color
    let accent: Color
    /// Drawn to the left of the title. Providers wear their glyph here, so the
    /// two cards are told apart by shape and never by colour: Smart Color owns
    /// the hue axis everywhere else in the app.
    @ViewBuilder let mark: () -> Mark
    @ViewBuilder let badge: () -> Badge
    @ViewBuilder let scene: () -> Scene
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            scene()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            metaFooter
        }
        .background(
            ZStack {
                Color.white.opacity(0.022)
                RadialGradient(
                    colors: [accent.opacity(0.10), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 220
                )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .rotationEffect(tiltAngle)
    }

    private var tiltAngle: Angle {
        switch tilt {
        case .left:  return .degrees(-0.3)
        case .right: return .degrees(0.3)
        }
    }

    private var metaFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                mark()
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 6)
                badge()
            }
            HStack(alignment: .top, spacing: 8) {
                HStack(alignment: .top, spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: statusColor.opacity(0.7), radius: 3)
                        .padding(.top, 4)
                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                control()
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.02), Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1),
            alignment: .top
        )
    }
}

/// The caption the provider cards wear where the old stamp used to sit: what
/// TokenEater reads to know about that provider. It answers the question the
/// stamp never did, which is what the app is actually looking at.
struct OnboardingSourceLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.42))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.04)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .lineLimit(1)
    }
}

/// The pill both provider cards use for a secondary action, so Re-detect looks
/// the same whichever card it sits on.
struct OnboardingActionButton: View {
    let label: String
    var isProminent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, isProminent ? 12 : 10)
                .padding(.vertical, isProminent ? 5 : 4)
                .background(background)
                .overlay(Capsule().stroke(Color.white.opacity(isProminent ? 0.18 : 0.12), lineWidth: 1))
                .shadow(color: isProminent ? DS.Palette.brandPrimary.opacity(0.4) : .clear, radius: 7)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var background: some View {
        if isProminent {
            Capsule().fill(LinearGradient(
                colors: [DS.Palette.brandPrimary, DS.Palette.brandPressed],
                startPoint: .top,
                endPoint: .bottom
            ))
        } else {
            Capsule().fill(Color.white.opacity(0.08))
        }
    }
}

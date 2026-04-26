import SwiftUI

/// Shared chrome for the 4 onboarding cards. The scene (top) is custom
/// content; the meta (bottom) is a structured row of title + badge +
/// status + control. Tint is per-card; alternating tilt is applied via
/// the `tilt` parameter.
struct OnboardingCard<Scene: View, Control: View>: View {
    enum Tilt { case left, right }
    enum Kind { case required, optional }

    let kind: Kind
    let tilt: Tilt
    let title: LocalizedStringResource
    let statusText: LocalizedStringResource
    let statusColor: Color
    let accent: Color
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
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                kindBadge
            }
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                        .shadow(color: statusColor.opacity(0.7), radius: 3)
                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
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

    @ViewBuilder
    private var kindBadge: some View {
        switch kind {
        case .required:
            Text("onboarding.badge.required")
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(Color(red: 0.78, green: 0.72, blue: 1.0))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color(red: 0.63, green: 0.51, blue: 1.0).opacity(0.16))
                )
                .overlay(
                    Capsule().stroke(Color(red: 0.63, green: 0.51, blue: 1.0).opacity(0.28), lineWidth: 1)
                )
        case .optional:
            Text("onboarding.badge.optional")
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.04)))
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }
}

import SwiftUI

struct WelcomeStep: View {
    @ObservedObject var viewModel: OnboardingViewModel

    private let demoValues: [(String, Int, Color)] = [
        ("5h", 35, Color(hex: "#22C55E")),
        ("7d", 52, Color(hex: "#FF9F0A")),
        ("Sonnet", 12, Color(hex: "#3B82F6")),
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)

            // Title
            GlowText(
                "TokenEater",
                font: .system(size: 28, weight: .bold, design: .rounded),
                color: .white,
                glowRadius: 6
            )

            Text("onboarding.welcome.subtitle")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            // Demo preview
            demoPreview
                .padding(.vertical, 4)

            Text("onboarding.welcome.description")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)

            Spacer()

            // CTA
            darkPrimaryButton("onboarding.continue") {
                viewModel.goNext()
            }
        }
        .padding(32)
    }

    private var demoPreview: some View {
        HStack(spacing: 24) {
            ForEach(demoValues, id: \.0) { label, value, color in
                VStack(spacing: 8) {
                    ZStack {
                        RingGauge(
                            percentage: value,
                            gradient: LinearGradient(colors: [color], startPoint: .leading, endPoint: .trailing),
                            size: 56,
                            glowColor: color,
                            glowRadius: 3
                        )
                        GlowText(
                            "\(value)%",
                            font: .system(size: 12, weight: .bold, design: .rounded),
                            color: color,
                            glowRadius: 2
                        )
                    }
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial.opacity(0.15))
        )
    }
}

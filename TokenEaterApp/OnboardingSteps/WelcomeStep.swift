import SwiftUI

struct WelcomeStep: View {
    @Bindable var viewModel: OnboardingViewModel

    // Demo data for preview gauges
    private let demoValues: [(String, Int, Color)] = [
        ("5h", 35, Color(hex: "#22C55E")),
        ("7d", 52, Color(hex: "#FF9F0A")),
        ("Sonnet", 12, Color(hex: "#3B82F6")),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // App icon
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)

            // Title
            Text("TokenEater")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            Text("onboarding.welcome.subtitle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Demo preview
            demoPreview
                .padding(.vertical, 4)

            Text("onboarding.welcome.description")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)

            Spacer()

            // CTA
            Button {
                viewModel.goNext()
            } label: {
                Text("onboarding.continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
    }

    private var demoPreview: some View {
        HStack(spacing: 24) {
            ForEach(demoValues, id: \.0) { label, value, color in
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(color.opacity(0.15), lineWidth: 6)
                            .frame(width: 56, height: 56)
                        Circle()
                            .trim(from: 0, to: CGFloat(value) / 100)
                            .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                        Text("\(value)%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

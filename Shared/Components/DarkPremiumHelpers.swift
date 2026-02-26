import SwiftUI

// MARK: - Glass Card

func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
}

// MARK: - Section Title

func sectionTitle(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(.white)
}

// MARK: - Card Label

func cardLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.5))
}

// MARK: - Dark Toggle

func darkToggle(_ label: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
        Text(label)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.8))
    }
    .toggleStyle(.switch)
    .tint(.blue)
}

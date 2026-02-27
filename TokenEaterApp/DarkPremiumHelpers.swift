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
    HStack {
        Toggle("", isOn: isOn)
            .toggleStyle(.switch)
            .tint(.blue)
            .labelsHidden()
        Text(label)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.8))
        Spacer()
    }
}

// MARK: - Dark Button (secondary)

func darkButton(_ titleKey: LocalizedStringResource, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(titleKey)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.white.opacity(0.08))
                    .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            )
    }
    .buttonStyle(.plain)
}

// MARK: - Dark Primary Button

func darkPrimaryButton(_ titleKey: LocalizedStringResource, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(titleKey)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.white.opacity(0.15))
                    .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
            )
    }
    .buttonStyle(.plain)
}

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

/// Unified header used by every settings section. Big display-weight title +
/// optional subtitle. Always leave 20pt of top breathing room.
func sectionTitle(_ text: String, subtitle: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(text)
            .font(.system(size: 24, weight: .black, design: .rounded))
            .foregroundStyle(.white)
        if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
    .padding(.top, 8)
    .padding(.bottom, 4)
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

// MARK: - Reset Section Button

/// Bottom-of-section reset control with a destructive confirmation alert.
/// Shared across settings sub-sections so the visual + interaction is
/// identical everywhere (Themes, Display, Popover, Watchers, Notifications,
/// Performance). Caller passes the localised confirmation title and the
/// closure that performs the actual reset.
struct ResetSectionButton: View {
    let confirmTitle: String
    let onReset: () -> Void

    @State private var showAlert = false

    var body: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                showAlert = true
            } label: {
                Text(String(localized: "settings.section.reset"))
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .alert(confirmTitle, isPresented: $showAlert) {
                Button(String(localized: "settings.section.reset.cancel"), role: .cancel) { }
                Button(String(localized: "settings.section.reset.action"), role: .destructive) {
                    onReset()
                }
            }
        }
    }
}

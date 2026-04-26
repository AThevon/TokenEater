import SwiftUI

/// Fourth card - gates the onboarding. Tapping Authorize fires the real
/// macOS Keychain prompt; the scene shows a stylised mock of the prompt
/// before tapping, then a spinner while authorising, then a checkmark
/// (or X with retry) afterwards.
struct ConnectCard: View {
    @ObservedObject var viewModel: OnboardingViewModel

    private let accent = Color(red: 0.42, green: 0.36, blue: 1.0) // violet

    var body: some View {
        OnboardingCard(
            kind: .required,
            tilt: .left,
            title: "onboarding.card.connect.title",
            statusText: statusText,
            statusColor: statusColor,
            accent: accent,
            scene: { scene },
            control: { control }
        )
    }

    @ViewBuilder
    private var scene: some View {
        switch viewModel.connectionStatus {
        case .idle:
            keychainDialogMock.padding(10)

        case .connecting:
            VStack(spacing: 7) {
                ProgressView().tint(.white)
                Text("onboarding.card.connect.connecting")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .success, .rateLimited:
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color(red: 0.30, green: 0.81, blue: 0.50).opacity(0.16))
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(red: 0.30, green: 0.81, blue: 0.50))
                }
                .shadow(color: Color(red: 0.30, green: 0.81, blue: 0.50).opacity(0.35), radius: 12)
                Text("onboarding.card.connect.success.scene")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.16))
                        .frame(width: 30, height: 30)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.94, green: 0.27, blue: 0.27))
                }
                Text("onboarding.card.connect.failed.scene")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
                Text(message)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var keychainDialogMock: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [.white, Color(white: 0.78)],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: 14
                    ))
                    .frame(width: 22, height: 22)
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(white: 0.25))
            }
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

            Text("onboarding.card.connect.keychain.title")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
            Text("onboarding.card.connect.keychain.sub")
                .font(.system(size: 7.5))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Text("onboarding.card.connect.keychain.deny")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.12), lineWidth: 1))

                Text("onboarding.card.connect.keychain.allow")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: [accent, Color(red: 0.31, green: 0.24, blue: 0.86)],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(accent.opacity(0.5), lineWidth: 1))
                    .shadow(color: accent.opacity(0.45), radius: 4)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.16).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .rotationEffect(.degrees(-0.6))
    }

    @ViewBuilder
    private var control: some View {
        switch viewModel.connectionStatus {
        case .idle:
            actionButton(label: "onboarding.card.connect.authorize") {
                viewModel.connect()
            }
        case .failed:
            actionButton(label: "onboarding.card.connect.retry") {
                viewModel.connectionStatus = .idle
            }
        case .connecting, .success, .rateLimited:
            EmptyView()
        }
    }

    private func actionButton(label: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(LinearGradient(colors: [accent, Color(red: 0.31, green: 0.24, blue: 0.86)],
                                                  startPoint: .top, endPoint: .bottom))
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: accent.opacity(0.4), radius: 6)
        }
        .buttonStyle(.plain)
    }

    private var statusText: LocalizedStringResource {
        switch viewModel.connectionStatus {
        case .idle:        return "onboarding.card.connect.status.idle"
        case .connecting:  return "onboarding.card.connect.status.connecting"
        case .success, .rateLimited:
            return "onboarding.card.connect.status.success"
        case .failed:      return "onboarding.card.connect.status.failed"
        }
    }

    private var statusColor: Color {
        switch viewModel.connectionStatus {
        case .idle, .connecting: return accent
        case .success, .rateLimited: return Color(red: 0.30, green: 0.81, blue: 0.50)
        case .failed: return Color(red: 0.94, green: 0.27, blue: 0.27)
        }
    }
}

import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var forward = true

    var body: some View {
        ZStack {
            AnimatedGradient(baseColors: [
                Color(red: 0.04, green: 0.04, blue: 0.10),
                Color(red: 0.08, green: 0.04, blue: 0.16),
            ])

            Group {
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeStep(viewModel: viewModel)
                case .prerequisites:
                    PrerequisiteStep(viewModel: viewModel)
                case .notifications:
                    NotificationStep(viewModel: viewModel)
                case .connection:
                    ConnectionStep(viewModel: viewModel)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
            ))
            .id(viewModel.currentStep)

            // Page dots
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                        Circle()
                            .fill(step == viewModel.currentStep ? Color.white : Color.white.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .onChange(of: viewModel.currentStep) { oldValue, newValue in
            forward = newValue.rawValue > oldValue.rawValue
        }
    }
}

import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            Group {
                switch viewModel.currentStep {
                case .welcome:
                    WelcomeStep(viewModel: viewModel)
                case .prerequisites:
                    PrerequisiteStep(viewModel: viewModel)
                case .connection:
                    ConnectionStep(viewModel: viewModel)
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .id(viewModel.currentStep)

            // Page dots
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step == viewModel.currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.currentStep)
                }
            }
            .padding(.bottom, 20)
        }
        .frame(width: 520, height: 480)
    }
}

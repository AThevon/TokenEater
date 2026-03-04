import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        ZStack {
            AnimatedGradient(baseColors: [
                Color(red: 0.10, green: 0.10, blue: 0.12),
                Color(red: 0.14, green: 0.10, blue: 0.18),
            ])

            VStack(spacing: 0) {
                Group {
                    switch viewModel.currentStep {
                    case .welcome:
                        WelcomeStep(viewModel: viewModel)
                    case .prerequisites:
                        PrerequisiteStep(viewModel: viewModel)
                    case .notifications:
                        NotificationStep(viewModel: viewModel)
                    case .agentWatchers:
                        AgentWatchersStep(viewModel: viewModel)
                    case .connection:
                        ConnectionStep(viewModel: viewModel)
                    }
                }
                .frame(maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: viewModel.isNavigatingForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: viewModel.isNavigatingForward ? .leading : .trailing).combined(with: .opacity)
                ))
                .id(viewModel.currentStep)

                HStack(spacing: 8) {
                    ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                        Circle()
                            .fill(step == viewModel.currentStep ? Color.white : Color.white.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }
}

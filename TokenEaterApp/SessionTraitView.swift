import SwiftUI

struct SessionTraitView: View {
    let session: ClaudeSession
    let isExpanded: Bool

    @State private var pulsing = false

    private var stateColor: Color {
        switch session.state {
        case .idle: return .green
        case .working: return .orange
        case .toolExec: return Color(red: 0.3, green: 0.6, blue: 1.0)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(stateColor)
                .frame(width: isExpanded ? 6 : 3, height: isExpanded ? 6 : 3)
                .opacity(session.state == .working ? (pulsing ? 1.0 : 0.4) : 1.0)
                .shadow(
                    color: session.state == .toolExec ? stateColor.opacity(0.6) : .clear,
                    radius: 3
                )

            if isExpanded {
                Text(session.projectName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, isExpanded ? 8 : 0)
        .padding(.vertical, isExpanded ? 4 : 0)
        .frame(
            width: isExpanded ? 120 : 3,
            height: isExpanded ? 22 : 14
        )
        .background {
            if isExpanded {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(stateColor.opacity(0.3), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(stateColor)
                    .opacity(session.state == .working ? (pulsing ? 1.0 : 0.4) : (session.isStale ? 0.3 : 0.8))
            }
        }
        .onAppear {
            if session.state == .working {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
        .onChange(of: session.state) { _, newState in
            if newState == .working {
                pulsing = false
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    pulsing = false
                }
            }
        }
    }
}

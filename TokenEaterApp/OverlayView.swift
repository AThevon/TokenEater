import SwiftUI

struct OverlayView: View {
    @EnvironmentObject var sessionStore: SessionStore

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: isHovering ? 4 : 6) {
            ForEach(sessionStore.activeSessions) { session in
                SessionTraitView(session: session, isExpanded: isHovering)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isHovering)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, isHovering ? 4 : 2)
        .onHover { hovering in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                isHovering = hovering
            }
        }
    }
}

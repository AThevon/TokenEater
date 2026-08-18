import SwiftUI
import AppKit

struct OverlayView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var overlayState: OverlayState

    @GestureState private var dragDelta: CGFloat = 0
    @State private var contentOffset: CGFloat = 0

    private var scale: CGFloat { CGFloat(settingsStore.overlayScale) }
    private var expandedHeight: CGFloat { 40 * scale }
    private var baseSpacing: CGFloat { 6 * scale }
    private var leftSide: Bool { overlayState.leftSide }

    var body: some View {
        VStack(alignment: leftSide ? .leading : .trailing, spacing: 4) {
            ForEach(Array(sessionStore.overlaySessions.enumerated()), id: \.element.id) { index, session in
                let prox = proximity(for: index, in: sessionStore.overlaySessions)

                SessionTraitView(session: session, proximity: prox, scale: scale, leftSide: leftSide) {
                    teleportToSession(session)
                }
                .animation(
                    .interactiveSpring(response: 0.18, dampingFraction: 0.78),
                    value: prox
                )
                .contextMenu { contextMenu(for: session) }
            }
        }
        .padding(.vertical, 12)
        .padding(leftSide ? .leading : .trailing, 8)
        .offset(y: contentOffset + dragDelta)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leftSide ? .leading : .trailing)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .updating($dragDelta) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    let maxOffset = overlayState.windowHeight / 2 - 50
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                        contentOffset += value.translation.height
                        contentOffset = max(-maxOffset, min(maxOffset, contentOffset))
                    }
                    overlayState.contentOffset = contentOffset
                }
        )
    }

    // MARK: - Dock-like proximity

    private func proximity(for index: Int, in sessions: [ClaudeSession]) -> CGFloat {
        guard let cursor = overlayState.cursorInWindow else { return 0 }

        let wWidth = overlayState.windowWidth
        let count = sessions.count
        let actualHeight = overlayState.windowHeight
        let totalHeight = CGFloat(count) * expandedHeight + CGFloat(max(0, count - 1)) * baseSpacing
        let startY = (actualHeight - totalHeight) / 2 + contentOffset + dragDelta

        // Vertical gate: only activate when cursor is near the items
        let groupCenterY = startY + totalHeight / 2
        let vDistToGroup = abs(groupCenterY - cursor.y)
        guard vDistToGroup < totalHeight / 2 + 80 else { return 0 }

        // Horizontal factor: visual expansion is tied to the controller's
        // active hover zone. While inactive the user needs to reach the
        // (possibly tiny) enter strip to trigger expansion; once active the
        // expansion persists across the larger exit zone so the user can
        // pin a session without pixel-hunting.
        let hActivationZone = max(overlayState.activationZone, 20)
        let hDistance = leftSide ? cursor.x : (wWidth - cursor.x)
        guard hDistance < hActivationZone else { return 0 }
        let rawH = 1 - (hDistance / hActivationZone)
        let hFactor = min(1, rawH * 3.0)

        let base: CGFloat = 0.75 * hFactor

        // Without dock effect: all cards expand uniformly
        guard settingsStore.overlayDockEffect else { return base }

        // Subtle dock bonus: closest item gets a small extra
        let itemCenterY = startY + CGFloat(index) * (expandedHeight + baseSpacing) + expandedHeight / 2
        let vDistance = abs(itemCenterY - cursor.y)
        let range: CGFloat = 120
        let bonus: CGFloat = 0.12

        if vDistance < range {
            let vFactor = (1 + cos(vDistance / range * .pi)) / 2
            return min(1, base + bonus * vFactor * hFactor)
        }

        return base
    }

    // MARK: - Context menu (#247)

    /// Right-click quick actions on a watcher card. Everything is
    /// non-destructive; "Hide" is scoped to the session's lifetime (the store
    /// forgets the id once the session leaves the scan).
    @ViewBuilder
    private func contextMenu(for session: ClaudeSession) -> some View {
        Button {
            teleportToSession(session)
        } label: {
            Label(String(localized: "watcher.menu.jump"), systemImage: "arrow.up.forward.square")
        }
        .disabled(session.processPid == nil)

        Divider()

        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: session.projectPath, isDirectory: true))
        } label: {
            Label(String(localized: "watcher.menu.openFinder"), systemImage: "folder")
        }

        Button {
            copyToPasteboard(session.projectPath)
        } label: {
            Label(String(localized: "watcher.menu.copyPath"), systemImage: "doc.on.doc")
        }

        Button {
            copyToPasteboard(session.id)
        } label: {
            Label(String(localized: "watcher.menu.copySessionId"), systemImage: "number")
        }

        if let transcriptPath = session.transcriptPath {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: transcriptPath)])
            } label: {
                Label(String(localized: "watcher.menu.revealTranscript"), systemImage: "doc.text.magnifyingglass")
            }
        }

        Divider()

        Button {
            sessionStore.hideSession(id: session.id)
        } label: {
            Label(String(localized: "watcher.menu.hide"), systemImage: "eye.slash")
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    // MARK: - Teleport

    private func teleportToSession(_ session: ClaudeSession) {
        guard let pid = session.processPid else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let processes = ProcessResolver.findClaudeProcesses()
            if let process = processes.first(where: { $0.pid == pid }) {
                ProcessResolver.activateTerminal(for: process)
            }
        }
    }
}

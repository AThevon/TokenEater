import SwiftUI

struct SessionTraitView: View {
    let session: ClaudeSession
    let proximity: CGFloat // 0 = collapsed capsule, 1 = fully expanded card
    var scale: CGFloat = 1.0
    var leftSide: Bool = false
    var onTap: (() -> Void)?

    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var isPressed = false
    @State private var breathing = false
    @State private var glowing = false
    @State private var nudging = false
    @State private var nudgePhase = false

    // MARK: - Display logic (simple vs detailed)

    private var isDetailed: Bool { settingsStore.watchersDetailedMode }

    private var needsAttention: Bool {
        session.state == .idle || session.state == .waiting
    }

    private var isActive: Bool {
        if isDetailed {
            switch session.state {
            case .thinking, .toolExec, .waiting, .subagent: return true
            case .idle, .compacting: return false
            }
        } else {
            switch session.state {
            case .idle, .waiting: return false
            case .thinking, .toolExec, .subagent, .compacting: return true
            }
        }
    }

    private var stateColor: Color {
        if isDetailed {
            switch session.state {
            case .idle: return Color(red: 0.3, green: 0.78, blue: 0.52)
            case .thinking: return Color(red: 0.95, green: 0.62, blue: 0.22)
            case .toolExec: return Color(red: 0.38, green: 0.58, blue: 0.95)
            case .waiting: return Color(red: 0.7, green: 0.45, blue: 0.95)
            case .subagent: return Color(red: 0.25, green: 0.85, blue: 0.85)
            case .compacting: return Color(red: 0.55, green: 0.55, blue: 0.60)
            }
        } else {
            switch session.state {
            case .idle, .waiting: return Color(red: 0.3, green: 0.78, blue: 0.52)
            case .thinking, .toolExec, .subagent, .compacting: return Color(red: 0.95, green: 0.62, blue: 0.22)
            }
        }
    }

    private var stateLabel: String {
        if isDetailed {
            switch session.state {
            case .idle: return "idle"
            case .thinking: return "thinking…"
            case .toolExec: return "executing"
            case .waiting: return "waiting…"
            case .subagent: return "subagent"
            case .compacting: return "compacting"
            }
        } else {
            switch session.state {
            case .idle, .waiting: return "idle"
            case .thinking, .toolExec, .subagent, .compacting: return "working…"
            }
        }
    }

    // MARK: - Interpolated dimensions

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * max(0, min(1, t))
    }

    private var itemWidth: CGFloat { lerp(5 * scale, 185 * scale, proximity) }
    private var itemHeight: CGFloat { lerp(22 * scale, 46 * scale, proximity) }
    private var cornerRadius: CGFloat { lerp(2.5, 10, proximity) }
    private var textOpacity: Double { min(1, max(0, Double(proximity - 0.35) / 0.3)) }
    private var materialOpacity: Double { min(1, max(0, Double(proximity - 0.15) / 0.5)) }
    private var barWidth: CGFloat { lerp(5 * scale, 3 * scale, proximity) }

    /// Nudge: horizontal scale for the whole capsule (expands outward)
    private var nudgeScaleX: CGFloat {
        guard nudging, nudgePhase else { return 1.0 }
        return 1.8
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: proximity > 0.15 ? 8 : 0) {
            if leftSide {
                textContent
                accentBar
            } else {
                accentBar
                textContent
            }
        }
        .padding(.horizontal, lerp(0, 10 * scale, proximity))
        .padding(.vertical, lerp(2 * scale, 8 * scale, proximity))
        .frame(width: itemWidth, height: itemHeight, alignment: leftSide ? .trailing : .leading)
        .background {
            ZStack {
                // Frosted glass (fades in)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(materialOpacity)

                // Solid color fill (fades out — visible only at low proximity)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(stateColor)
                    .opacity(max(0, 1 - materialOpacity) * 0.85)

                // Subtle state-colored border on expanded card
                if proximity > 0.3 {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(stateColor.opacity(0.15), lineWidth: 0.5)
                        .opacity(materialOpacity)
                }
            }
        }
        // Glow on collapsed capsules when active
        .shadow(
            color: isActive && proximity < 0.3
                ? stateColor.opacity(glowing ? 0.7 : 0.2)
                : .black.opacity(Double(proximity) * 0.1),
            radius: isActive && proximity < 0.3 ? (glowing ? 8 : 3) : 6,
            y: isActive && proximity < 0.3 ? 0 : 2
        )
        .scaleEffect(x: nudgeScaleX, y: 1.0, anchor: leftSide ? .leading : .trailing)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .onTapGesture {
            guard proximity > 0.3 else { return }
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    isPressed = false
                }
                onTap?()
            }
        }
        .onAppear { updateAnimations() }
        .onChange(of: session.state) { oldState, newState in
            // Nudge: start bouncing when transitioning to an attention state
            let wasAttention = (oldState == .idle || oldState == .waiting)
            let isAttention = (newState == .idle || newState == .waiting)
            if !wasAttention && isAttention {
                startNudge()
            } else if !isAttention {
                stopNudge()
            }
            updateAnimations()
        }
        .onChange(of: proximity > 0.15) { _, isNear in
            // Stop nudge when user hovers close enough to see the session
            if isNear && nudging {
                stopNudge()
            }
        }
        .onChange(of: settingsStore.watcherAnimationsEnabled) { _, enabled in
            if enabled {
                updateAnimations()
            } else {
                stopNudge()
                withAnimation(.easeInOut(duration: 0.3)) {
                    breathing = false
                    glowing = false
                }
            }
        }
    }

    @ViewBuilder
    private var accentBar: some View {
        RoundedRectangle(cornerRadius: lerp(2.5, 1.5, proximity))
            .fill(stateColor)
            .frame(width: barWidth)
            .opacity(session.state == .thinking ? (breathing ? 1.0 : 0.65) : 0.9)
    }

    @ViewBuilder
    private var textContent: some View {
        if proximity > 0.15 {
            if leftSide {
                Spacer(minLength: 0)
            }

            VStack(alignment: leftSide ? .trailing : .leading, spacing: 2 * scale) {
                Text(session.projectName)
                    .font(.system(size: 11.5 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(stateLabel)
                    .font(.system(size: 9 * scale, weight: .medium, design: .rounded))
                    .foregroundStyle(stateColor.opacity(0.85))
            }
            .opacity(textOpacity)

            if !leftSide {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Animations

    private func startNudge() {
        guard settingsStore.watcherAnimationsEnabled else { return }
        nudgePhase = false
        nudging = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.4).repeatForever(autoreverses: true)) {
            nudgePhase = true
        }
    }

    private func stopNudge() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            nudging = false
            nudgePhase = false
        }
    }

    private func updateAnimations() {
        guard settingsStore.watcherAnimationsEnabled else {
            breathing = false
            glowing = false
            return
        }

        // Breathing for accent bar (only .thinking state)
        if session.state == .thinking {
            breathing = false
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                breathing = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                breathing = false
            }
        }

        // Glow for collapsed capsules
        if isActive {
            glowing = false
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glowing = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                glowing = false
            }
        }
    }
}

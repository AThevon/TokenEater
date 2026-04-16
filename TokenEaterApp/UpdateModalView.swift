import SwiftUI

struct UpdateModalView: View {
    @EnvironmentObject private var updateStore: UpdateStore
    @EnvironmentObject private var themeStore: ThemeStore

    @State private var iconFloat: Bool = false
    @State private var shimmerOffset: CGFloat = -200
    @State private var checkmarkScale: CGFloat = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            // Backdrop blur
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isBlockingState { updateStore.dismissUpdateModal() }
                }

            // Modal card
            VStack(spacing: 0) {
                switch updateStore.updateState {
                case .available(let version, _, _, _):
                    availableContent(newVersion: version)
                case .downloading(let progress):
                    downloadingContent(progress: progress)
                case .downloaded:
                    downloadedContent
                case .installing:
                    installingContent
                case .error(let message):
                    errorContent(message: message)
                default:
                    EmptyView()
                }
            }
            .padding(32)
            .frame(width: 380)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial.opacity(0.2))
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: accentColor.opacity(0.15), radius: 40, y: 10)
            .opacity(contentOpacity)
            .scaleEffect(contentOpacity == 0 ? 0.92 : 1.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1
            }
        }
    }

    // MARK: - Available State

    private func availableContent(newVersion: String) -> some View {
        VStack(spacing: 24) {
            // Floating app icon with glow
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: accentColor.opacity(0.3), radius: 12)
                        .offset(y: iconFloat ? -3 : 3)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    iconFloat = true
                }
            }

            // Title
            VStack(spacing: 8) {
                Text(String(localized: "update.available.title"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text(String(localized: "update.available.subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Version badges
            HStack(spacing: 16) {
                versionBadge(updateStore.currentVersion, isCurrent: true)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(0.6))
                versionBadge(newVersion, isCurrent: false)
            }

            // Buttons
            VStack(spacing: 12) {
                shimmerButton(String(localized: "update.download")) {
                    updateStore.downloadUpdate()
                }

                Button(String(localized: "update.later")) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        contentOpacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        updateStore.dismissUpdateModal()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    // MARK: - Downloading State

    private func downloadingContent(progress: Double) -> some View {
        VStack(spacing: 24) {
            // Ring gauge progress
            ZStack {
                // Background glow
                Circle()
                    .fill(accentColor.opacity(0.06))
                    .frame(width: 140, height: 140)
                    .blur(radius: 25)

                RingGauge(
                    percentage: Int(progress * 100),
                    gradient: themeStore.current.gaugeGradient(for: 30, thresholds: themeStore.thresholds),
                    size: 120,
                    glowColor: accentColor,
                    glowRadius: 8
                )

                // Percentage text
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: accentColor.opacity(0.5), radius: 4)
                    Text("%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .contentTransition(.numericText(countsDown: false))
                .animation(.spring(response: 0.3), value: Int(progress * 100))
            }

            VStack(spacing: 6) {
                Text(String(localized: "update.downloading"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Text(String(localized: "update.downloading.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Downloaded State

    private var downloadedContent: some View {
        VStack(spacing: 24) {
            // Success checkmark
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                        .frame(width: 72, height: 72)
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.green)
                        .shadow(color: .green.opacity(0.5), radius: 4)
                }
                .scaleEffect(checkmarkScale)
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    checkmarkScale = 1
                }
            }

            VStack(spacing: 8) {
                Text(String(localized: "update.ready.title"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text(String(localized: "update.ready.subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            VStack(spacing: 12) {
                shimmerButton(String(localized: "update.install")) {
                    updateStore.installUpdate()
                }

                Text(String(localized: "update.install.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
    }

    // MARK: - Installing State

    @State private var installRotation: Double = 0

    private var installingContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                ZStack {
                    Circle()
                        .stroke(accentColor.opacity(0.1), lineWidth: 3)
                        .frame(width: 72, height: 72)

                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(installRotation))

                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .shadow(color: accentColor.opacity(0.5), radius: 4)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    installRotation = 360
                }
            }

            VStack(spacing: 8) {
                Text(String(localized: "update.installing"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                Text(String(localized: "update.installing.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
    }

    // MARK: - Error State

    private func errorContent(message: String) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .blur(radius: 20)

                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 2)
                        .frame(width: 72, height: 72)
                    Image(systemName: "xmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.red)
                }
            }

            VStack(spacing: 8) {
                Text("Install failed")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .lineLimit(5)
            }

            Button("Dismiss") {
                updateStore.dismissUpdateModal()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - Components

    private func versionBadge(_ version: String, isCurrent: Bool) -> some View {
        VStack(spacing: 4) {
            Text(isCurrent ? String(localized: "update.version.current") : String(localized: "update.version.new"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
                .textCase(.uppercase)
                .tracking(0.5)
            Text("v\(version)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(isCurrent ? .white.opacity(0.5) : accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? .white.opacity(0.04) : accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isCurrent ? .white.opacity(0.06) : accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func shimmerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        Capsule()
                            .fill(accentColor.opacity(0.2))
                        Capsule()
                            .stroke(accentColor.opacity(0.4), lineWidth: 1)

                        // Shimmer
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.08), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: shimmerOffset)
                            .mask(Capsule())
                    }
                )
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }
    }

    // MARK: - Helpers

    private var accentColor: Color {
        themeStore.current.gaugeColor(for: 30, thresholds: themeStore.thresholds)
    }

    private var isBlockingState: Bool {
        switch updateStore.updateState {
        case .downloading, .installing: return true
        default: return false
        }
    }
}

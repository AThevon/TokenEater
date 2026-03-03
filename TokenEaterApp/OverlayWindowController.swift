import AppKit
import SwiftUI
import Combine

@MainActor
final class OverlayWindowController {
    private var window: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private let sessionStore: SessionStore
    private let settingsStore: SettingsStore

    init(sessionStore: SessionStore, settingsStore: SettingsStore) {
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore

        observeSettings()
    }

    private func observeSettings() {
        settingsStore.$overlayEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.showOverlay()
                } else {
                    self?.hideOverlay()
                }
            }
            .store(in: &cancellables)

        sessionStore.$sessions
            .map { sessions in sessions.contains { !$0.isDead } }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] hasActive in
                guard self?.settingsStore.overlayEnabled == true else { return }
                if hasActive {
                    self?.showOverlay()
                } else {
                    self?.hideOverlay()
                }
            }
            .store(in: &cancellables)
    }

    private func showOverlay() {
        guard window == nil else {
            window?.orderFront(nil)
            return
        }

        let overlayView = OverlayView()
            .environmentObject(sessionStore)

        let hostingView = NSHostingView(rootView: overlayView)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.contentView = hostingView
        window.isReleasedWhenClosed = false

        positionWindow(window)
        window.orderFront(nil)

        self.window = window

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let w = self?.window { self?.positionWindow(w) }
        }
    }

    private func hideOverlay() {
        window?.orderOut(nil)
        window = nil
    }

    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let windowHeight: CGFloat = 300
        let x = screenFrame.maxX - 10
        let y = screenFrame.midY - windowHeight / 2

        window.setFrame(NSRect(x: x, y: y, width: 140, height: windowHeight), display: true)
    }
}

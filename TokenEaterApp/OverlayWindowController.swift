import AppKit
import SwiftUI
import Combine

@MainActor
final class OverlayState: ObservableObject {
    @Published var cursorInWindow: CGPoint? = nil
    @Published var windowHeight: CGFloat = 800
    @Published var windowWidth: CGFloat = 200
    @Published var leftSide: Bool = false
}

@MainActor
final class OverlayWindowController {
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private let sessionStore: SessionStore
    private let settingsStore: SettingsStore
    let overlayState = OverlayState()
    private var lastCursorCheck: CFAbsoluteTime = 0

    private var windowWidth: CGFloat {
        let base: CGFloat = 200
        let expandedCard: CGFloat = 185 * CGFloat(settingsStore.overlayScale) + 20
        return max(base, expandedCard)
    }
    private var interactiveZone: CGFloat { min(windowWidth, 120 * CGFloat(settingsStore.overlayScale)) }

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
                guard let self, self.settingsStore.overlayEnabled, self.settingsStore.sessionMonitorEnabled else { return }
                if hasActive {
                    self.showOverlay()
                } else {
                    self.hideOverlay()
                }
            }
            .store(in: &cancellables)

        // Hide overlay when session monitor is disabled
        settingsStore.$sessionMonitorEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if !enabled {
                    self.hideOverlay()
                } else if self.settingsStore.overlayEnabled {
                    self.showOverlay()
                }
            }
            .store(in: &cancellables)

        // Reposition when scale or side changes
        Publishers.MergeMany(
            settingsStore.$overlayScale.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.$overlayLeftSide.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.repositionIfNeeded()
        }
        .store(in: &cancellables)
    }

    private func repositionIfNeeded() {
        guard let panel else { return }
        overlayState.windowWidth = windowWidth
        overlayState.leftSide = settingsStore.overlayLeftSide
        positionPanel(panel)
    }

    private func showOverlay() {
        guard panel == nil else {
            panel?.orderFront(nil)
            return
        }

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelHeight = screenFrame.height

        let overlayView = OverlayView()
            .environmentObject(sessionStore)
            .environmentObject(settingsStore)
            .environmentObject(overlayState)

        let w = windowWidth
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = NSRect(x: 0, y: 0, width: w, height: panelHeight)
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false

        positionPanel(panel)
        panel.orderFront(nil)

        overlayState.windowHeight = panelHeight
        overlayState.windowWidth = w
        overlayState.leftSide = settingsStore.overlayLeftSide
        self.panel = panel

        // Global monitor: tracks cursor everywhere (works even when ignoresMouseEvents = true)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateCursorTracking()
        }
        // Local monitor: tracks cursor and drags when panel is interactive
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.updateCursorTracking()
            return event
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.panel else { return }
                self.positionPanel(p)
                self.overlayState.windowHeight = p.frame.height
            }
        }
    }

    private func hideOverlay() {
        if let gm = globalMonitor { NSEvent.removeMonitor(gm) }
        if let lm = localMonitor { NSEvent.removeMonitor(lm) }
        globalMonitor = nil
        localMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let w = windowWidth

        let x = settingsStore.overlayLeftSide
            ? screenFrame.minX
            : screenFrame.maxX - w

        panel.setFrame(NSRect(x: x, y: screenFrame.minY, width: w, height: screenFrame.height), display: true)
    }

    private func updateCursorTracking() {
        // Throttle to ~20Hz — global mouse monitor fires at 60Hz+
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastCursorCheck >= 0.05 else { return }
        lastCursorCheck = now

        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame

        guard mouse.x >= frame.minX && mouse.x <= frame.maxX &&
              mouse.y >= frame.minY && mouse.y <= frame.maxY else {
            // Only fire objectWillChange if it was non-nil
            if overlayState.cursorInWindow != nil {
                overlayState.cursorInWindow = nil
            }
            panel.ignoresMouseEvents = true
            return
        }

        // Convert screen coords (AppKit Y-up) → SwiftUI coords (Y-down)
        let localX = mouse.x - frame.minX
        let localY = frame.height - (mouse.y - frame.minY)
        let point = CGPoint(x: localX, y: localY)

        // Only update if cursor moved more than 1pt (avoid sub-pixel churn)
        if let prev = overlayState.cursorInWindow,
           abs(prev.x - point.x) < 1 && abs(prev.y - point.y) < 1 {
            // Still update interactive zone without triggering SwiftUI re-render
        } else {
            overlayState.cursorInWindow = point
        }

        // Keep interactive during active drags (don't break mid-drag)
        if NSEvent.pressedMouseButtons & 1 != 0 {
            panel.ignoresMouseEvents = false
            return
        }

        // Interactive zone: edge-side area — click-through everywhere else
        let distanceFromEdge = settingsStore.overlayLeftSide ? localX : (frame.width - localX)
        panel.ignoresMouseEvents = distanceFromEdge > interactiveZone
    }
}

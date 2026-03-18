import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private let popover = NSPopover()
    private var dashboardWindow: NSWindow?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private let usageStore: UsageStore
    private let themeStore: ThemeStore
    private let settingsStore: SettingsStore
    private let updateStore: UpdateStore
    private let sessionStore: SessionStore
    private let tokenFileMonitor: TokenFileMonitorProtocol

    init(
        usageStore: UsageStore,
        themeStore: ThemeStore,
        settingsStore: SettingsStore,
        updateStore: UpdateStore,
        sessionStore: SessionStore,
        tokenFileMonitor: TokenFileMonitorProtocol = TokenFileMonitor()
    ) {
        self.usageStore = usageStore
        self.themeStore = themeStore
        self.settingsStore = settingsStore
        self.updateStore = updateStore
        self.sessionStore = sessionStore
        self.tokenFileMonitor = tokenFileMonitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem.isVisible = settingsStore.showMenuBar

        super.init()

        setupStatusItem()
        setupPopover()
        observeStoreChanges()
        observeDashboardRequest()
        observeAppActivation()

        if settingsStore.hasCompletedOnboarding {
            bootstrapRefresh()
        } else {
            observeOnboardingForRefresh()
        }

        DispatchQueue.main.async { [weak self] in
            self?.showDashboard()
        }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        button.action = #selector(statusBarClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp])
        updateMenuBarIcon()
    }

    private func setupPopover() {
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
    }

    private func installPopoverContent() {
        let popoverView = MenuBarPopoverView()
            .environmentObject(usageStore)
            .environmentObject(themeStore)
            .environmentObject(settingsStore)
            .environmentObject(updateStore)
        popover.contentViewController = NSHostingController(rootView: popoverView)
    }

    private func observeStoreChanges() {
        Publishers.MergeMany(
            usageStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            themeStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateMenuBarIcon()
        }
        .store(in: &cancellables)

        settingsStore.$pacingMargin
            .removeDuplicates()
            .sink { [weak self] newMargin in
                self?.usageStore.pacingMargin = newMargin
                self?.usageStore.recalculatePacing()
            }
            .store(in: &cancellables)

        settingsStore.$refreshInterval
            .removeDuplicates()
            .sink { [weak self] newInterval in
                self?.usageStore.refreshIntervalSeconds = TimeInterval(newInterval)
            }
            .store(in: &cancellables)

        settingsStore.$showMenuBar
            .removeDuplicates()
            .sink { [weak self] visible in
                self?.statusItem.isVisible = visible
            }
            .store(in: &cancellables)
    }

    private func bootstrapRefresh() {
        usageStore.proxyConfig = settingsStore.proxyConfig
        usageStore.pacingMargin = settingsStore.pacingMargin
        usageStore.refreshIntervalSeconds = TimeInterval(settingsStore.refreshInterval)
        usageStore.reloadConfig(thresholds: themeStore.thresholds)
        usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
        themeStore.syncToSharedFile()

        // Monitor token files (credentials + config.json) for changes
        tokenFileMonitor.startMonitoring()
        tokenFileMonitor.tokenChanged
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.usageStore.switchToFastMode()
                Task { await self.usageStore.refresh(force: true) }
            }
            .store(in: &cancellables)

        // Refresh after wake from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.usageStore.refreshIfStale()
            }
        }
    }

    private func observeOnboardingForRefresh() {
        settingsStore.$hasCompletedOnboarding
            .removeDuplicates()
            .filter { $0 }
            .first()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.bootstrapRefresh()
            }
            .store(in: &cancellables)
    }

    private func observeDashboardRequest() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDashboardRequest(_:)),
            name: .openDashboard,
            object: nil
        )
    }

    private func observeAppActivation() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
        WidgetReloader.scheduleReload(delay: 0.1)
    }

    @objc private func handleDashboardRequest(_ notification: Notification) {
        showDashboard()

        if let section = notification.userInfo?["section"] as? String,
           let target = AppSection(rawValue: section) {
            NotificationCenter.default.post(name: .navigateToSection, object: nil, userInfo: ["section": target.rawValue])
        }
    }

    // MARK: - Menu Bar Icon

    private func updateMenuBarIcon() {
        let image = MenuBarRenderer.render(MenuBarRenderer.RenderData(
            pinnedMetrics: settingsStore.pinnedMetrics,
            fiveHourPct: usageStore.fiveHourPct,
            sevenDayPct: usageStore.sevenDayPct,
            sonnetPct: usageStore.sonnetPct,
            pacingDelta: usageStore.pacingDelta,
            pacingZone: usageStore.pacingZone,
            pacingDisplayMode: settingsStore.pacingDisplayMode,
            hasConfig: usageStore.hasConfig,
            hasError: usageStore.hasError,
            themeColors: themeStore.current,
            thresholds: themeStore.thresholds,
            menuBarMonochrome: themeStore.menuBarMonochrome
        ))
        statusItem.button?.image = image
    }

    // MARK: - Click handling

    @objc private func statusBarClicked() {
        togglePopover()
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            popover.contentViewController = nil
            stopEventMonitor()
        } else {
            guard let button = statusItem.button else { return }
            installPopoverContent()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startEventMonitor()
        }
    }

    func showDashboard() {
        popover.performClose(nil)
        popover.contentViewController = nil
        stopEventMonitor()

        if let window = dashboardWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let appView = MainAppView()
            .environmentObject(usageStore)
            .environmentObject(themeStore)
            .environmentObject(settingsStore)
            .environmentObject(updateStore)
            .environmentObject(sessionStore)

        let isOnboarding = !settingsStore.hasCompletedOnboarding
        let size = isOnboarding ? NSSize(width: 680, height: 660) : NSSize(width: 820, height: 580)
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        if !isOnboarding { styleMask.insert(.resizable) }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.delegate = self

        let hostingController = NSHostingController(rootView: appView)
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.setContentSize(size)
        window.center()

        if isOnboarding {
            window.minSize = size
            window.maxSize = size
        } else {
            window.minSize = NSSize(width: 720, height: 450)
            window.setFrameAutosaveName("TokenEaterMain")
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.dashboardWindow = window
        observeOnboardingCompletion()
    }

    private func observeOnboardingCompletion() {
        settingsStore.$hasCompletedOnboarding
            .dropFirst()
            .filter { $0 }
            .first()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.transitionToMainWindow()
            }
            .store(in: &cancellables)
    }

    private func transitionToMainWindow() {
        guard let window = dashboardWindow else { return }
        window.styleMask.insert(.resizable)
        window.contentMinSize = NSSize(width: 720, height: 450)
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.minSize = NSSize(width: 720, height: 450)
        window.setFrameAutosaveName("TokenEaterMain")
        let mainSize = NSSize(width: 820, height: 580)
        window.setContentSize(mainSize)
        window.center()
    }

    // MARK: - Event Monitor

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
            self?.popover.contentViewController = nil
            self?.stopEventMonitor()
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - NSWindowDelegate

extension StatusBarController: NSWindowDelegate {
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            if !self.settingsStore.hasCompletedOnboarding {
                // User closed during onboarding — quit the app so they're not stuck
                // (LSUIElement app has no Dock icon, no Force Quit entry)
                NSApp.terminate(nil)
                return
            }
            sender.contentViewController = nil
            sender.orderOut(nil)
            self.dashboardWindow = nil
        }
        return false
    }
}

// MARK: - Notification

extension Notification.Name {
    static let openDashboard = Notification.Name("openDashboard")
    static let navigateToSection = Notification.Name("navigateToSection")
}

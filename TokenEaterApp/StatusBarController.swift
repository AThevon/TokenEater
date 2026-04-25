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
        // Accept both primary and secondary clicks so we can route right-click
        // (and trackpad two-finger tap - macOS surfaces those as rightMouseUp)
        // to a contextual menu while keeping left-click tied to the popover.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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

        Timer.publish(every: 60, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self,
                      self.settingsStore.pinnedMetrics.contains(.sessionReset) else { return }
                self.usageStore.refreshResetCountdown()
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
        usageStore.notifTogglesProvider = { [weak self] in
            guard let self else { return nil }
            return NotificationToggles(
                trackFiveHour: self.settingsStore.notifTrackFiveHour,
                trackWeekly: self.settingsStore.notifTrackWeekly,
                trackSonnet: self.settingsStore.notifTrackSonnet,
                trackDesign: self.settingsStore.notifTrackDesign,
                sendRecovery: self.settingsStore.notifSendRecovery,
                pacingHot: self.settingsStore.notifPacingHot,
                pacingWarning: self.settingsStore.notifPacingWarning,
                resetReminderSession: self.settingsStore.notifResetReminderSession,
                resetReminderWeekly: self.settingsStore.notifResetReminderWeekly,
                extraCredits: self.settingsStore.notifExtraCredits,
                tokenExpired: self.settingsStore.notifTokenExpired,
                smartColorEnabled: self.settingsStore.smartColorEnabled,
                thresholds: self.themeStore.thresholds
            )
        }
        usageStore.reloadConfig(thresholds: themeStore.thresholds)
        usageStore.startAutoRefresh(thresholds: themeStore.thresholds)
        themeStore.syncToSharedFile()

        // Monitor token files (credentials + config.json) for changes
        tokenFileMonitor.startMonitoring()
        tokenFileMonitor.tokenChanged
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.usageStore.handleTokenChange()
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
           let target = NavigationTarget.parse(section) {
            let payload: String
            if let sub = target.settingsSection {
                payload = "settings.\(sub.rawValue)"
            } else {
                payload = target.space.rawValue
            }
            NotificationCenter.default.post(name: .navigateToSection, object: nil, userInfo: ["section": payload])
        }
    }

    // MARK: - Menu Bar Icon

    private func updateMenuBarIcon() {
        let image = MenuBarRenderer.render(MenuBarRenderer.RenderData(
            pinnedMetrics: settingsStore.pinnedMetrics,
            displaySonnet: settingsStore.displaySonnet,
            fiveHourPct: usageStore.fiveHourPct,
            sevenDayPct: usageStore.sevenDayPct,
            sonnetPct: usageStore.sonnetPct,
            weeklyPacingDelta: Int(usageStore.pacingResult?.delta ?? 0),
            weeklyPacingZone: usageStore.pacingResult?.zone ?? .onTrack,
            hasWeeklyPacing: usageStore.pacingResult != nil,
            sessionPacingDelta: Int(usageStore.fiveHourPacing?.delta ?? 0),
            sessionPacingZone: usageStore.fiveHourPacing?.zone ?? .onTrack,
            hasSessionPacing: usageStore.fiveHourPacing != nil,
            sessionPacingDisplayMode: settingsStore.sessionPacingDisplayMode,
            weeklyPacingDisplayMode: settingsStore.weeklyPacingDisplayMode,
            hasConfig: usageStore.hasConfig,
            hasError: usageStore.hasError,
            themeColors: themeStore.current,
            thresholds: themeStore.thresholds,
            menuBarMonochrome: themeStore.menuBarMonochrome,
            fiveHourReset: usageStore.fiveHourReset,
            fiveHourResetAbsolute: usageStore.fiveHourResetAbsolute,
            fiveHourResetDate: usageStore.lastUsage?.fiveHour?.resetsAtDate,
            sevenDayResetDate: usageStore.lastUsage?.sevenDay?.resetsAtDate,
            sonnetResetDate: usageStore.lastUsage?.sevenDaySonnet?.resetsAtDate,
            designResetDate: usageStore.lastUsage?.sevenDayDesign?.resetsAtDate,
            hasFiveHourBucket: usageStore.lastUsage?.fiveHour != nil,
            resetDisplayFormat: settingsStore.resetDisplayFormat,
            resetTextColorHex: settingsStore.resetTextColorHex,
            sessionPeriodColorHex: settingsStore.sessionPeriodColorHex,
            smartResetColor: settingsStore.smartColorEnabled,
            menuBarStyle: settingsStore.menuBarStyle,
            pacingShape: settingsStore.pacingShape,
            designPct: usageStore.designPct,
            hasDesign: usageStore.hasDesign
        ))
        statusItem.button?.image = image
    }

    // MARK: - Click handling

    @objc private func statusBarClicked() {
        // Right-click or control-click routes to the contextual menu so users
        // get quick access to the most common actions (refresh, variant
        // switching, settings shortcuts, quit) without opening the popover.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            showContextMenu()
            return
        }
        togglePopover()
    }

    // MARK: - Context menu (right-click)

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        let menu = buildContextMenu()
        // Temporarily attach + popUp + detach so the menu appears anchored
        // under the status item button without hijacking left-click.
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Actions
        let refresh = NSMenuItem(
            title: String(localized: "contextmenu.refresh"),
            action: #selector(contextRefresh),
            keyEquivalent: "r"
        )
        refresh.target = self
        refresh.isEnabled = !usageStore.isLoading
        menu.addItem(refresh)

        let openDashboard = NSMenuItem(
            title: String(localized: "contextmenu.open"),
            action: #selector(contextOpenDashboard),
            keyEquivalent: ""
        )
        openDashboard.target = self
        menu.addItem(openDashboard)

        menu.addItem(.separator())

        // Popover layout submenu
        let variantItem = NSMenuItem(
            title: String(localized: "contextmenu.variant"),
            action: nil,
            keyEquivalent: ""
        )
        let variantSub = NSMenu()
        for variant in PopoverVariant.allCases {
            let item = NSMenuItem(
                title: variant.localizedLabel,
                action: #selector(contextSelectVariant(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = variant.rawValue
            item.state = (settingsStore.popoverConfig.activeVariant == variant) ? .on : .off
            variantSub.addItem(item)
        }
        variantItem.submenu = variantSub
        menu.addItem(variantItem)

        // Watchers toggle
        let watchersLabel = settingsStore.overlayEnabled
            ? String(localized: "contextmenu.watchers.disable")
            : String(localized: "contextmenu.watchers.enable")
        let watchers = NSMenuItem(
            title: watchersLabel,
            action: #selector(contextToggleWatchers),
            keyEquivalent: ""
        )
        watchers.target = self
        watchers.state = settingsStore.overlayEnabled ? .on : .off
        menu.addItem(watchers)

        menu.addItem(.separator())

        // Settings submenu (direct section shortcuts)
        let settingsItem = NSMenuItem(
            title: String(localized: "contextmenu.settings"),
            action: nil,
            keyEquivalent: ""
        )
        let settingsSub = NSMenu()
        for section in SettingsSection.allCases {
            let item = NSMenuItem(
                title: section.label,
                action: #selector(contextOpenSection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = "settings.\(section.rawValue)"
            settingsSub.addItem(item)
        }
        settingsItem.submenu = settingsSub
        menu.addItem(settingsItem)

        let updates = NSMenuItem(
            title: String(localized: "contextmenu.updates"),
            action: #selector(contextCheckUpdates),
            keyEquivalent: ""
        )
        updates.target = self
        menu.addItem(updates)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "menubar.quit"),
            action: #selector(contextQuit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func contextRefresh() {
        Task { await usageStore.refresh(force: true) }
    }

    @objc private func contextOpenDashboard() {
        showDashboard()
    }

    @objc private func contextSelectVariant(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let variant = PopoverVariant(rawValue: raw) else { return }
        settingsStore.popoverConfig.activeVariant = variant
    }

    @objc private func contextToggleWatchers() {
        settingsStore.overlayEnabled.toggle()
    }

    @objc private func contextOpenSection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        showDashboard()
        NotificationCenter.default.post(
            name: .navigateToSection,
            object: nil,
            userInfo: ["section": raw]
        )
    }

    @objc private func contextCheckUpdates() {
        updateStore.checkForUpdates()
    }

    @objc private func contextQuit() {
        NSApp.terminate(nil)
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
            NSApp.activate(ignoringOtherApps: true)
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
        let size = isOnboarding ? NSSize(width: 700, height: 720) : NSSize(width: 940, height: 700)
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
        // Keep drag limited to the titlebar area. With this on, clicking +
        // holding on any padding / empty space in the sidebar, the settings
        // panels, or the popover editor would drag the whole window by
        // accident - now only the invisible titlebar strip (~28px up top,
        // where the traffic lights sit) moves it.
        window.isMovableByWindowBackground = false
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
            window.minSize = NSSize(width: 600, height: 440)
            window.contentMinSize = NSSize(width: 600, height: 440)
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
        window.contentMinSize = NSSize(width: 600, height: 440)
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.minSize = NSSize(width: 600, height: 440)
        window.setFrameAutosaveName("TokenEaterMain")
        let mainSize = NSSize(width: 940, height: 700)
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
                // User closed during onboarding - quit the app so they're not stuck
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

    /// Hard-clamp the resize so AppKit can't honor a frame smaller than our
    /// declared min, even if `setFrameAutosaveName` restored a stale frame
    /// or the user drags the resize grip past the floor. Belt-and-braces
    /// for the `minSize` / `contentMinSize` properties.
    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, 600),
            height: max(frameSize.height, 440)
        )
    }
}

// MARK: - Notification

extension Notification.Name {
    static let openDashboard = Notification.Name("openDashboard")
    static let navigateToSection = Notification.Name("navigateToSection")
}

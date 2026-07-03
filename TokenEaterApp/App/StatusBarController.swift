import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private let popover = NSPopover()
    private var dashboardWindow: NSWindow?
    private var eventMonitor: Any?
    private var localKeyMonitor: Any?
    private var appDeactivateObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var countdownCancellable: AnyCancellable?

    private let usageStore: UsageStore
    private let themeStore: ThemeStore
    private let settingsStore: SettingsStore
    private let updateStore: UpdateStore
    private let sessionStore: SessionStore
    private let vendorStatusStore: VendorStatusStore
    private let tokenFileMonitor: TokenFileMonitorProtocol

    init(
        usageStore: UsageStore,
        themeStore: ThemeStore,
        settingsStore: SettingsStore,
        updateStore: UpdateStore,
        sessionStore: SessionStore,
        vendorStatusStore: VendorStatusStore,
        tokenFileMonitor: TokenFileMonitorProtocol = TokenFileMonitor()
    ) {
        self.usageStore = usageStore
        self.themeStore = themeStore
        self.settingsStore = settingsStore
        self.updateStore = updateStore
        self.sessionStore = sessionStore
        self.vendorStatusStore = vendorStatusStore
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

        // Auto-open the dashboard at launch unless the user opted into a
        // background (menu-bar-only) launch. Onboarding ALWAYS opens: the
        // window hosts the onboarding flow and, being an LSUIElement app with
        // no Dock icon, suppressing it on a fresh install would strand the user
        // with no reachable UI (#198). The window stays reachable from the menu
        // bar's right-click "Open" item afterwards.
        if !settingsStore.hasCompletedOnboarding || !settingsStore.launchInBackground {
            DispatchQueue.main.async { [weak self] in
                self?.showDashboard()
            }
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
        // .applicationDefined (not .transient): NSPopover's own transient
        // event-tracking dismisses the popover on the first mouse move when it
        // is opened over a fullscreen-app Space. We keep full control of
        // dismissal instead (see startPopoverDismissMonitors): click-outside,
        // Escape, app-deactivation (Cmd-Tab) and Space changes all close it, so
        // it matches the .transient behaviour on the desktop while no longer
        // self-dismissing over fullscreen.
        popover.behavior = .applicationDefined
        popover.appearance = NSAppearance(named: .darkAqua)
    }

    private func installPopoverContent() {
        let popoverView = MenuBarPopoverView()
            .environmentObject(usageStore)
            .environmentObject(themeStore)
            .environmentObject(settingsStore)
            .environmentObject(updateStore)
            .environmentObject(vendorStatusStore)
        popover.contentViewController = NSHostingController(rootView: popoverView)
    }

    private func observeStoreChanges() {
        Publishers.MergeMany(
            usageStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            themeStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            vendorStatusStore.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateMenuBarIcon()
            self?.updateCountdownTimer()
        }
        .store(in: &cancellables)

        Timer.publish(every: 60, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self,
                      self.settingsStore.pinnedMetrics.contains(.sessionReset) else { return }
                self.usageStore.refreshResetCountdown()
            }
            .store(in: &cancellables)

        settingsStore.pacing.$margin
            .removeDuplicates()
            .sink { [weak self] newMargin in
                self?.usageStore.pacingMargin = newMargin
                self?.usageStore.recalculatePacing()
            }
            .store(in: &cancellables)

        // Any workweek-schedule change (toggle / days / hours) re-bases the
        // expected pace. Deferred to the main run loop so the schedule is read
        // AFTER @Published's willSet has committed every new value, then
        // recompute and reload the widget (which reads the schedule from the
        // shared file the settingsStore wrote in its didSet).
        Publishers.MergeMany(
            settingsStore.pacing.$workweekEnabled.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.pacing.$activeDays.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.pacing.$hoursEnabled.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.pacing.$startHour.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.pacing.$endHour.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.usageStore.pacingSchedule = self.settingsStore.pacingSchedule
            self.usageStore.recalculatePacing()
            WidgetReloader.scheduleReload()
        }
        .store(in: &cancellables)

        settingsStore.$refreshInterval
            .removeDuplicates()
            .sink { [weak self] newInterval in
                self?.usageStore.refreshIntervalSeconds = TimeInterval(newInterval)
            }
            .store(in: &cancellables)

        settingsStore.$statusPollInterval
            .removeDuplicates()
            .sink { [weak self] newInterval in
                self?.vendorStatusStore.healthyPollInterval = TimeInterval(newInterval)
            }
            .store(in: &cancellables)

        settingsStore.$outageMonitoringEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.vendorStatusStore.start() }
                else { self.vendorStatusStore.stop() }
            }
            .store(in: &cancellables)

        settingsStore.display.$showMenuBar
            .removeDuplicates()
            .sink { [weak self] visible in
                self?.statusItem.isVisible = visible
            }
            .store(in: &cancellables)
    }

    private func bootstrapRefresh() {
        usageStore.proxyConfig = settingsStore.proxyConfig
        usageStore.pacingMargin = settingsStore.pacingMargin
        usageStore.pacingSchedule = settingsStore.pacingSchedule
        usageStore.refreshIntervalSeconds = TimeInterval(settingsStore.refreshInterval)
        usageStore.notifTogglesProvider = { [weak self] in self?.makeNotificationToggles() }
        vendorStatusStore.notifTogglesProvider = { [weak self] in self?.makeNotificationToggles() }
        vendorStatusStore.healthyPollInterval = TimeInterval(settingsStore.statusPollInterval)
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

        if settingsStore.outageMonitoringEnabled {
            vendorStatusStore.start()
        }
    }

    /// Single source of truth for the notification-toggle bundle, shared by the
    /// usage store and the vendor-status store so they always agree.
    private func makeNotificationToggles() -> NotificationToggles {
        NotificationToggles(
            masterEnabled: settingsStore.notificationsEnabled,
            trackFiveHour: settingsStore.notifTrackFiveHour,
            trackWeekly: settingsStore.notifTrackWeekly,
            trackSonnet: settingsStore.notifTrackSonnet,
            trackDesign: settingsStore.notifTrackDesign,
            sendRecovery: settingsStore.notifSendRecovery,
            pacingHot: settingsStore.notifPacingHot,
            pacingWarning: settingsStore.notifPacingWarning,
            resetReminderSession: settingsStore.notifResetReminderSession,
            resetReminderWeekly: settingsStore.notifResetReminderWeekly,
            resetReminderSessionOffsetMinutes: settingsStore.notifResetReminderSessionOffset,
            resetReminderWeeklyOffsetMinutes: settingsStore.notifResetReminderWeeklyOffset,
            extraCredits: settingsStore.notifExtraCredits,
            tokenExpired: settingsStore.notifTokenExpired,
            smartColorEnabled: settingsStore.smartColorEnabled,
            smartColorProfile: settingsStore.smartColorProfile,
            pacingMargin: Double(settingsStore.pacingMargin),
            thresholds: themeStore.thresholds,
            vendorDegraded: settingsStore.notifVendorDegraded,
            vendorRestored: settingsStore.notifVendorRestored
        )
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
            smartColorProfile: settingsStore.smartColorProfile,
            pacingMargin: Double(settingsStore.pacingMargin),
            menuBarStyle: settingsStore.menuBarStyle,
            pacingShape: settingsStore.pacingShape,
            designPct: usageStore.designPct,
            hasDesign: usageStore.hasDesign,
            outageActive: settingsStore.statusShowMenuBarBadge && vendorStatusStore.isDegraded,
            outageHealth: vendorStatusStore.worstHealth,
            nextPollSeconds: vendorStatusStore.nextPollDate.map { max(0, Int(ceil($0.timeIntervalSinceNow))) },
            extraCreditsPct: usageStore.extraCreditsPct,
            hasExtraCredits: usageStore.hasExtraCredits
        ))
        statusItem.button?.image = image
    }

    /// Run a 1-second redraw ONLY while an outage badge is visible, so the
    /// menu-bar countdown ticks without waking the CPU every second otherwise.
    private func updateCountdownTimer() {
        let badgeCountdown = settingsStore.statusShowMenuBarBadge && vendorStatusStore.isDegraded
        let pinCountdown = settingsStore.pinnedMetrics.contains(.serviceStatus) && vendorStatusStore.worstHealth == .down
        let active = badgeCountdown || pinCountdown
        if active, countdownCancellable == nil {
            countdownCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.updateMenuBarIcon() }
        } else if !active {
            countdownCancellable?.cancel()
            countdownCancellable = nil
        }
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
            dismissPopover()
        } else {
            guard let button = statusItem.button else { return }
            installPopoverContent()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            stylePopoverWindow()
            startPopoverDismissMonitors()
        }
    }

    /// Post-show fixes for the popover's own window. Runs on the next runloop
    /// turn because the NSPopover window isn't attached synchronously after show.
    private func stylePopoverWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let popoverWindow = self.popover.contentViewController?.view.window else { return }

            // Fullscreen fix: a menu-bar popover opened over a fullscreen-app
            // Space is created on the default Space, so the cursor over the
            // visible popover reads as "outside" and the .transient behaviour
            // dismisses it on the first mouse move. Let the popover window join
            // the active (fullscreen) Space so the cursor registers as inside.
            popoverWindow.collectionBehavior.insert(.canJoinAllSpaces)
            popoverWindow.collectionBehavior.insert(.fullScreenAuxiliary)

            // Arrow-colour fix: on macOS 26 the NSPopoverFrame draws its arrow
            // with a translucent (glass) material while our content is opaque,
            // so the bare arrow shows through. There is no NSVisualEffectView to
            // tint; paint an opaque backing on the frame view itself (which is
            // clipped to the popover shape, arrow included) below the content.
            if let frameView = self.popover.contentViewController?.view.superview {
                // Idempotent: NSPopover reuses the same frame view across opens,
                // so drop any tint left by a previous open before adding a new one
                // (otherwise one NSView + layer leaks per open).
                let tintID = NSUserInterfaceItemIdentifier("popoverArrowTint")
                frameView.subviews
                    .filter { $0.identifier == tintID }
                    .forEach { $0.removeFromSuperview() }
                let tint = NSView(frame: frameView.bounds)
                tint.identifier = tintID
                tint.autoresizingMask = [.width, .height]
                tint.wantsLayer = true
                tint.layer?.backgroundColor = Self.popoverBackgroundColor.cgColor
                frameView.addSubview(tint, positioned: .below, relativeTo: frameView.subviews.first)
            }
        }
    }

    /// Opaque dark shared by the popover layouts (see ClassicLayoutView).
    private static let popoverBackgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)

    func showDashboard() {
        dismissPopover()

        // Promote to a regular app (Dock icon + app menu) while the dashboard
        // is open so it feels like a real window; windowShouldClose drops back
        // to .accessory (menu-bar-only) when the window is closed, so the Dock
        // icon is only present while the window actually is.
        NSApp.setActivationPolicy(.regular)

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
            .environmentObject(vendorStatusStore)

        let isOnboarding = !settingsStore.hasCompletedOnboarding
        let onboardingSize = NSSize(
            width: DS.Layout.onboardingWindow.width,
            height: DS.Layout.onboardingWindow.height
        )
        let size = isOnboarding ? onboardingSize : NSSize(width: 940, height: 700)
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
        // Keep drag limited to the titlebar area in dashboard mode. With
        // this on for the dashboard, clicking + holding on any padding /
        // empty space in the sidebar, the settings panels, or the popover
        // editor would drag the whole window by accident. For onboarding,
        // the user has a fixed-size panel without a sidebar - we let them
        // drag from anywhere on the background so the window doesn't feel
        // stuck behind the titlebar strip.
        window.isMovableByWindowBackground = isOnboarding
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

    /// Observe onboarding state in BOTH directions so the NSWindow stays
    /// in sync with what the SwiftUI view is rendering. Without this, the
    /// "replay onboarding" path leaves the window at the dashboard size
    /// (940x700) while the SwiftUI body switches to onboardingContent,
    /// producing the empty-margin ghost effect.
    private func observeOnboardingCompletion() {
        settingsStore.$hasCompletedOnboarding
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] completed in
                if completed {
                    self?.transitionToMainWindow()
                } else {
                    self?.transitionToOnboardingWindow()
                }
            }
            .store(in: &cancellables)
    }

    private func transitionToMainWindow() {
        guard let window = dashboardWindow else { return }
        window.styleMask.insert(.resizable)
        window.contentMinSize = NSSize(width: 600, height: 440)
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.minSize = NSSize(width: 600, height: 440)
        window.isMovableByWindowBackground = false
        window.setFrameAutosaveName("TokenEaterMain")
        let mainSize = NSSize(width: 940, height: 700)
        window.setContentSize(mainSize)
        window.center()
    }

    /// Inverse of `transitionToMainWindow`: shrink the dashboard window
    /// back to the onboarding size when the user resets onboarding from
    /// Settings.
    private func transitionToOnboardingWindow() {
        guard let window = dashboardWindow else { return }
        window.styleMask.remove(.resizable)
        let onboardingSize = NSSize(
            width: DS.Layout.onboardingWindow.width,
            height: DS.Layout.onboardingWindow.height
        )
        window.contentMinSize = onboardingSize
        window.contentMaxSize = onboardingSize
        window.minSize = onboardingSize
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("")
        window.setContentSize(onboardingSize)
        window.center()
    }

    // MARK: - Event Monitor

    private func startPopoverDismissMonitors() {
        // Click into another app closes the popover.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissPopover()
        }
        // Escape closes it. A key event is delivered to our own app, so it never
        // reaches the global monitor above - a local monitor is required.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }   // 53 = Escape
            self?.dismissPopover()
            return nil
        }
        // App deactivation (Cmd-Tab, clicking another app) and Space changes
        // close it too, restoring the dismissal .transient gave us for free
        // before we switched to .applicationDefined for the fullscreen fix.
        appDeactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismissPopover()
        }
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.dismissPopover()
        }
    }

    /// Close the popover and tear down every dismissal monitor/observer.
    private func dismissPopover() {
        popover.performClose(nil)
        popover.contentViewController = nil
        stopPopoverDismissMonitors()
    }

    private func stopPopoverDismissMonitors() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let observer = appDeactivateObserver {
            NotificationCenter.default.removeObserver(observer)
            appDeactivateObserver = nil
        }
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceChangeObserver = nil
        }
    }
}

// MARK: - NSWindowDelegate

extension StatusBarController: NSWindowDelegate {
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            if !self.settingsStore.hasCompletedOnboarding {
                // User closed during onboarding: quit rather than sit
                // half-onboarded and unconnected in the menu bar.
                NSApp.terminate(nil)
                return
            }
            sender.contentViewController = nil
            sender.orderOut(nil)
            self.dashboardWindow = nil
            // Closing the dashboard (not quitting) returns the app to
            // menu-bar-only: drop the Dock icon + app menu.
            NSApp.setActivationPolicy(.accessory)
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

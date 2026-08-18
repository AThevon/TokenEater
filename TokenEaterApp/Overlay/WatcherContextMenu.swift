import AppKit
import SwiftUI

/// Native right-click menu for a watcher card (#247).
///
/// AppKit `NSMenu` instead of SwiftUI `.contextMenu` on purpose: the SwiftUI
/// bridge rebuilds its items whenever the underlying row re-renders, and the
/// overlay re-renders on every scan tick (~2s) plus on every cursor move, so
/// the open menu visibly twitched. An `NSMenu` is built once per popup from a
/// value snapshot and tracks in its own run loop, immune to SwiftUI updates.
/// The menu delegate also gives exact open/close hooks, which the overlay
/// uses to freeze its hover state while the menu is up (otherwise the cards
/// collapse as soon as the cursor travels onto the menu).
struct WatcherContextMenuCatcher: NSViewRepresentable {
    let session: ClaudeSession
    let onJump: () -> Void
    let onHide: () -> Void
    let onMenuOpen: () -> Void
    let onMenuClose: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.coordinator = context.coordinator
        context.coordinator.configure(with: self)
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        context.coordinator.configure(with: self)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator (menu construction + actions)

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        private var session: ClaudeSession?
        private var onJump: (() -> Void)?
        private var onHide: (() -> Void)?
        private var onMenuOpen: (() -> Void)?
        private var onMenuClose: (() -> Void)?

        func configure(with parent: WatcherContextMenuCatcher) {
            session = parent.session
            onJump = parent.onJump
            onHide = parent.onHide
            onMenuOpen = parent.onMenuOpen
            onMenuClose = parent.onMenuClose
        }

        func makeMenu() -> NSMenu? {
            guard let session else { return nil }
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false

            let jump = item("watcher.menu.jump", symbol: "arrow.up.forward.square", action: #selector(jump))
            jump.isEnabled = session.processPid != nil
            menu.addItem(jump)

            menu.addItem(.separator())
            menu.addItem(item("watcher.menu.openFinder", symbol: "folder", action: #selector(openInFinder)))
            menu.addItem(item("watcher.menu.copyPath", symbol: "doc.on.doc", action: #selector(copyPath)))
            menu.addItem(item("watcher.menu.copySessionId", symbol: "number", action: #selector(copySessionId)))
            if session.transcriptPath != nil {
                menu.addItem(item("watcher.menu.revealTranscript", symbol: "doc.text.magnifyingglass", action: #selector(revealTranscript)))
            }

            menu.addItem(.separator())
            menu.addItem(item("watcher.menu.hide", symbol: "eye.slash", action: #selector(hide)))
            return menu
        }

        private func item(_ key: String.LocalizationValue, symbol: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: String(localized: key), action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return item
        }

        // MARK: Actions

        @objc private func jump() { onJump?() }

        @objc private func openInFinder() {
            guard let session else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: session.projectPath, isDirectory: true))
        }

        @objc private func copyPath() {
            guard let session else { return }
            copyToPasteboard(session.projectPath)
        }

        @objc private func copySessionId() {
            guard let session else { return }
            copyToPasteboard(session.id)
        }

        @objc private func revealTranscript() {
            guard let transcriptPath = session?.transcriptPath else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: transcriptPath)])
        }

        @objc private func hide() { onHide?() }

        private func copyToPasteboard(_ string: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }

        // MARK: NSMenuDelegate (overlay freeze window)

        nonisolated func menuWillOpen(_ menu: NSMenu) {
            MainActor.assumeIsolated { onMenuOpen?() }
        }

        nonisolated func menuDidClose(_ menu: NSMenu) {
            MainActor.assumeIsolated { onMenuClose?() }
        }
    }

    // MARK: - Catcher view (right-click interception, everything else passes)

    final class CatcherView: NSView {
        weak var coordinator: Coordinator?

        override func rightMouseDown(with event: NSEvent) {
            popMenu(with: event)
        }

        override func mouseDown(with event: NSEvent) {
            // ctrl+click is the keyboard-flavored context menu on macOS.
            if event.modifierFlags.contains(.control) {
                popMenu(with: event)
            } else {
                super.mouseDown(with: event)
            }
        }

        private func popMenu(with event: NSEvent) {
            guard let menu = coordinator?.makeMenu() else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        /// Claim only context-menu events. Returning nil for everything else
        /// keeps left clicks, hovers and drags flowing to the SwiftUI card
        /// underneath (tap-to-teleport and the reposition drag stay intact).
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            case .leftMouseDown where event.modifierFlags.contains(.control):
                return super.hitTest(point)
            default:
                return nil
            }
        }
    }
}

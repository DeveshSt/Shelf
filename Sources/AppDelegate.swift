import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mainWindow = MainWindowController()
    private let dropWindow = DropWindowController()
    private var statusItem: NSStatusItem?

    private static let firstWindowShownKey = "hasShownFirstWindow"

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = FileStore.shared
        _ = SettingsStore.shared

        applyPresence()
        startDragMonitor()

        NotificationCenter.default.addObserver(
            self, selector: #selector(dropCornerChanged),
            name: .dropCornerChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(presenceChanged),
            name: .appPresenceChanged, object: nil
        )

        // First launch ever: open the main window so the user sees the app.
        // After that, launch silently (great for "Open at Login").
        if !UserDefaults.standard.bool(forKey: Self.firstWindowShownKey) {
            UserDefaults.standard.set(true, forKey: Self.firstWindowShownKey)
            mainWindow.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app: keep running when the window closes.
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return true
    }

    // MARK: - Menu bar

    private func installMenuBar() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let img = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Shelf")
            img?.isTemplate = true
            button.image = img
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    private func removeMenuBar() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    private func applyPresence() {
        let p = SettingsStore.shared.appPresence
        switch p {
        case .menuBar:
            NSApp.setActivationPolicy(.accessory)
            installMenuBar()
        case .dock:
            NSApp.setActivationPolicy(.regular)
            removeMenuBar()
        case .both:
            NSApp.setActivationPolicy(.regular)
            installMenuBar()
        }
    }

    @objc private func presenceChanged() {
        applyPresence()
    }

    @objc private func dropCornerChanged() {
        dropWindow.repositionToCorner()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showStatusMenu(sender)
        } else {
            mainWindow.show()
        }
    }

    private func showStatusMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        let count = FileStore.shared.items.count
        let header = NSMenuItem(title: "Shelf — \(count) item\(count == 1 ? "" : "s")", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Shelf", action: #selector(openMain), keyEquivalent: "")
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(revealStaging), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear All", action: #selector(clearAll), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Shelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != nil && item.target == nil {
            item.target = self
        }
        statusItem?.menu = menu
        sender.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openMain()      { mainWindow.show() }
    @objc private func revealStaging() { FileStore.shared.revealInFinder() }
    @objc private func clearAll()      { FileStore.shared.clearAll() }

    // MARK: - Drag detection

    private func startDragMonitor() {
        DragMonitor.shared.onFileDragStart = { [weak self] in
            self?.dropWindow.show()
        }
        DragMonitor.shared.onDragEnd = { [weak self] in
            self?.dropWindow.hide()
        }
        DragMonitor.shared.start()
    }
}

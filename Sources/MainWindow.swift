import AppKit
import SwiftUI

/// Owns the main window. We build it manually so we get the exact translucent
/// "space grey" chrome we want.
final class MainWindowController {
    private var window: NSWindow?

    func show() {
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }

        let size = NSSize(width: 760, height: 500)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        w.title = "Shelf"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.minSize = NSSize(width: 640, height: 420)
        w.appearance = NSAppearance(named: .vibrantDark)
        w.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1.0)
        w.isReleasedWhenClosed = false
        w.center()

        let host = NSHostingView(rootView: MainContentView())
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        w.contentView = host

        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

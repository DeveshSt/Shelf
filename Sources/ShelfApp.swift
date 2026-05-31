import SwiftUI
import AppKit

@main
struct ShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene — AppDelegate manages all windows manually so we get
        // precise control over the main window, drop window, and menu bar item.
        Settings { EmptyView() }
    }
}

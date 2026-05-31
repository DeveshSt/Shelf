import SwiftUI
import AppKit
import Combine
import ServiceManagement

enum AppPresence: String, CaseIterable, Identifiable {
    case menuBar, dock, both
    var id: String { rawValue }
    var label: String {
        switch self {
        case .menuBar: return "Menu Bar"
        case .dock:    return "Dock"
        case .both:    return "Both"
        }
    }
    var icon: String {
        switch self {
        case .menuBar: return "menubar.rectangle"
        case .dock:    return "dock.rectangle"
        case .both:    return "rectangle.on.rectangle"
        }
    }
}

/// Tiny wrapper around SMAppService.mainApp for "Open at Login".
enum ShelfLoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    static func set(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("Shelf: login item toggle failed: \(error.localizedDescription)")
        }
    }
}

enum DropCorner: String, CaseIterable, Identifiable {
    case bottomLeft, bottomRight, topLeft, topRight, bottomCenter
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bottomLeft:   return "Bottom Left"
        case .bottomRight:  return "Bottom Right"
        case .topLeft:      return "Top Left"
        case .topRight:     return "Top Right"
        case .bottomCenter: return "Bottom Center"
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, graphite
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue:     return Color(red: 0.32, green: 0.55, blue: 1.00)
        case .purple:   return Color(red: 0.69, green: 0.45, blue: 1.00)
        case .pink:     return Color(red: 1.00, green: 0.42, blue: 0.71)
        case .red:      return Color(red: 1.00, green: 0.38, blue: 0.38)
        case .orange:   return Color(red: 1.00, green: 0.60, blue: 0.20)
        case .yellow:   return Color(red: 1.00, green: 0.83, blue: 0.27)
        case .green:    return Color(red: 0.36, green: 0.85, blue: 0.55)
        case .graphite: return Color(white: 0.78)
        }
    }
    var label: String { rawValue.capitalized }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Keys {
        static let accent = "accent"
        static let dropCorner = "dropCorner"
        static let autoHideSeconds = "autoHideSeconds"
        static let appPresence = "appPresence"
    }

    @Published var accent: AccentChoice {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Keys.accent) }
    }
    @Published var dropCorner: DropCorner {
        didSet {
            UserDefaults.standard.set(dropCorner.rawValue, forKey: Keys.dropCorner)
            NotificationCenter.default.post(name: .dropCornerChanged, object: nil)
        }
    }
    @Published var autoHideSeconds: Double {
        didSet { UserDefaults.standard.set(autoHideSeconds, forKey: Keys.autoHideSeconds) }
    }
    @Published var appPresence: AppPresence {
        didSet {
            UserDefaults.standard.set(appPresence.rawValue, forKey: Keys.appPresence)
            NotificationCenter.default.post(name: .appPresenceChanged, object: nil)
        }
    }
    /// Launch-at-login is sourced directly from SMAppService so it stays in
    /// sync with what macOS actually knows about.
    @Published var launchAtLogin: Bool {
        didSet { ShelfLoginItem.set(enabled: launchAtLogin) }
    }

    init() {
        let d = UserDefaults.standard
        self.accent = AccentChoice(rawValue: d.string(forKey: Keys.accent) ?? "") ?? .blue
        self.dropCorner = DropCorner(rawValue: d.string(forKey: Keys.dropCorner) ?? "") ?? .bottomLeft
        let auto = d.object(forKey: Keys.autoHideSeconds) as? Double
        self.autoHideSeconds = auto ?? 2.0
        self.appPresence = AppPresence(rawValue: d.string(forKey: Keys.appPresence) ?? "") ?? .menuBar
        self.launchAtLogin = ShelfLoginItem.isEnabled
    }
}

extension Notification.Name {
    static let dropCornerChanged  = Notification.Name("ShelfDropCornerChanged")
    static let appPresenceChanged = Notification.Name("ShelfAppPresenceChanged")
    static let shelfFileDropped   = Notification.Name("ShelfFileDropped")
}

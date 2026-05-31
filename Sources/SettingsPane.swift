import SwiftUI
import AppKit

struct SettingsPane: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var store = FileStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                storageSection
                startupSection
                accentSection
                positionSection
                behaviorSection
                aboutSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Startup & visibility

    private var startupSection: some View {
        SettingsSection(title: "Startup & Visibility") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Where to show Shelf")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        ForEach(AppPresence.allCases) { p in
                            PresenceChip(
                                presence: p,
                                isSelected: settings.appPresence == p,
                                accent: settings.accent.color
                            ) {
                                settings.appPresence = p
                            }
                        }
                    }
                    Text(presenceHint(settings.appPresence))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Divider().opacity(0.15)

                Toggle(isOn: $settings.launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Start Shelf automatically when you log in. The window stays closed — only the icon appears.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .tint(settings.accent.color)
            }
        }
    }

    private func presenceHint(_ p: AppPresence) -> String {
        switch p {
        case .menuBar: return "Shelf lives quietly in the top menu bar. No Dock icon."
        case .dock:    return "Shelf shows in the Dock only. Click its icon to open the window."
        case .both:    return "Shelf shows in both the menu bar and the Dock."
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        SettingsSection(title: "Shelf Folder") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Files dropped on the shelf are stored in this folder.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))

                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(settings.accent.color)
                        .frame(width: 18)
                    Text(displayPath(store.stagingDir))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )

                HStack(spacing: 8) {
                    Button {
                        pickStagingFolder()
                    } label: {
                        Label("Change…", systemImage: "folder.badge.gearshape")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(settings.accent.color.opacity(0.22)))
                            .foregroundStyle(settings.accent.color)
                    }
                    .buttonStyle(.plain)

                    Button {
                        resetStagingFolder()
                    } label: {
                        Text("Reset to Default")
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.stagingDir.standardizedFileURL.path == FileStore.defaultStagingDir.standardizedFileURL.path)

                    Spacer()
                    Button {
                        store.revealInFinder()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                }
            }
        }
    }

    private func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func pickStagingFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Shelf Folder"
        panel.prompt = "Select"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.stagingDir.deletingLastPathComponent()
        panel.begin { response in
            guard response == .OK, let newURL = panel.url else { return }
            promptThenApply(newDir: newURL)
        }
    }

    private func resetStagingFolder() {
        let target = FileStore.defaultStagingDir
        promptThenApply(newDir: target)
    }

    private func promptThenApply(newDir: URL) {
        // If shelf is empty, just switch — no need to ask.
        guard !store.items.isEmpty else {
            _ = store.setStagingDir(newDir, mode: .leaveExisting)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Move existing files to the new folder?"
        alert.informativeText = "You have \(store.items.count) item\(store.items.count == 1 ? "" : "s") in the current shelf folder. Choose what to do with them."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move Files")     // .alertFirstButtonReturn
        alert.addButton(withTitle: "Leave in Place") // .alertSecondButtonReturn
        alert.addButton(withTitle: "Cancel")         // .alertThirdButtonReturn
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:  _ = store.setStagingDir(newDir, mode: .moveExisting)
        case .alertSecondButtonReturn: _ = store.setStagingDir(newDir, mode: .leaveExisting)
        default: break
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Make Shelf feel like yours.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var accentSection: some View {
        SettingsSection(title: "Accent Color") {
            HStack(spacing: 10) {
                ForEach(AccentChoice.allCases) { choice in
                    Button {
                        settings.accent = choice
                    } label: {
                        ZStack {
                            Circle().fill(choice.color)
                            if settings.accent == choice {
                                Circle().strokeBorder(Color.white, lineWidth: 2)
                                    .padding(2)
                            }
                        }
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(choice.label)
                }
            }
        }
    }

    private var positionSection: some View {
        SettingsSection(title: "Drop Zone Position") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where the floating drop zone appears when you start dragging.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(DropCorner.allCases) { corner in
                        CornerChip(
                            corner: corner,
                            isSelected: settings.dropCorner == corner,
                            accent: settings.accent.color
                        ) {
                            settings.dropCorner = corner
                        }
                    }
                }
            }
        }
    }

    private var behaviorSection: some View {
        SettingsSection(title: "Behavior") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Auto-hide drop zone after")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(settings.autoHideSeconds, specifier: "%.1f")s")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(settings.accent.color)
                }
                Slider(value: $settings.autoHideSeconds, in: 0.5...6.0, step: 0.5)
                    .tint(settings.accent.color)
                Text("How long the drop zone stays visible after you stop dragging.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Shelf 1.0")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("A little dropbox for short-term stuff. Drag screenshots and files in, drag them out whenever.")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.45))
            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
        }
    }
}

struct PresenceChip: View {
    let presence: AppPresence
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: presence.icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(presence.label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(hovering ? 0.9 : 0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.28) : (hovering ? Color.white.opacity(0.05) : Color.white.opacity(0.02)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(isSelected ? accent.opacity(0.75) : Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CornerChip: View {
    let corner: DropCorner
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                cornerGlyph
                    .frame(width: 22, height: 16)
                Text(corner.label)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 1.0 : 0.75))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.25) : (hovering ? Color.white.opacity(0.05) : Color.white.opacity(0.02)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? accent.opacity(0.7) : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var cornerGlyph: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: alignment) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: w, height: h)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isSelected ? accent : Color.white.opacity(0.55))
                    .frame(width: 7, height: 7)
                    .padding(1.5)
            }
        }
    }

    private var alignment: Alignment {
        switch corner {
        case .bottomLeft:   return .bottomLeading
        case .bottomRight:  return .bottomTrailing
        case .topLeft:      return .topLeading
        case .topRight:     return .topTrailing
        case .bottomCenter: return .bottom
        }
    }
}

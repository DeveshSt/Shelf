import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MainContentView: View {
    @ObservedObject private var store = FileStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var selectedTab: Tab = .shelf
    @State private var isTargeted = false

    enum Tab: String, CaseIterable, Identifiable {
        case shelf, settings
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .shelf: return "tray.full"
            case .settings: return "gearshape"
            }
        }
        var label: String {
            switch self {
            case .shelf: return "Shelf"
            case .settings: return "Settings"
            }
        }
    }

    var body: some View {
        ZStack {
            // Background — space grey gradient + subtle vignette
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.07)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 180)
                Divider().opacity(0.25)
                Group {
                    switch selectedTab {
                    case .shelf: ShelfPane(isTargeted: $isTargeted)
                    case .settings: SettingsPane()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .tint(settings.accent.color)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title block
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(settings.accent.color.opacity(0.18))
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundStyle(settings.accent.color)
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(width: 28, height: 28)
                Text("Shelf")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 22)

            // Tabs
            VStack(spacing: 4) {
                ForEach(Tab.allCases) { tab in
                    SidebarRow(
                        icon: tab.icon,
                        label: tab.label,
                        isActive: selectedTab == tab,
                        accent: settings.accent.color
                    ) { selectedTab = tab }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Footer info
            VStack(alignment: .leading, spacing: 4) {
                Text("STAGING FOLDER")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(0.8)
                Text(store.stagingDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Button {
                    store.revealInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(settings.accent.color)
                .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .background(Color.black.opacity(0.18))
    }
}

struct SidebarRow: View {
    let icon: String
    let label: String
    let isActive: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular, design: .rounded))
                Spacer()
            }
            .foregroundStyle(isActive ? Color.white : Color.white.opacity(hovering ? 0.85 : 0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? accent.opacity(0.22) : (hovering ? Color.white.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Shelf pane

struct ShelfPane: View {
    @ObservedObject private var store = FileStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Binding var isTargeted: Bool

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            ZStack {
                if store.items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.items) { item in
                                FileTile(item: item, accent: settings.accent.color)
                            }
                        }
                        .padding(20)
                    }
                }
                if isTargeted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(settings.accent.color, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [.fileURL, .image, .pdf, .movie, .item], isTargeted: $isTargeted) { providers in
                FileStore.shared.ingest(providers: providers)
                return true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Stashed")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("\(store.items.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Spacer()
            Button {
                store.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Refresh")

            Menu {
                Button {
                    exportAsZip()
                } label: {
                    Label("Save as Zip…", systemImage: "doc.zipper")
                }
                Button {
                    exportAsFolder()
                } label: {
                    Label("Save as Folder…", systemImage: "folder")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(settings.accent.color.opacity(0.18)))
                    .foregroundStyle(settings.accent.color)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(store.items.isEmpty)
            .opacity(store.items.isEmpty ? 0.4 : 1.0)

            Button {
                store.clearAll()
            } label: {
                Label("Clear All", systemImage: "trash")
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .disabled(store.items.isEmpty)
            .opacity(store.items.isEmpty ? 0.4 : 1.0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    // MARK: - Export

    private func defaultExportFilename(ext: String?) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let date = df.string(from: Date())
        return ext.map { "Shelf \(date).\($0)" } ?? "Shelf \(date)"
    }

    private func exportAsZip() {
        let panel = NSSavePanel()
        panel.title = "Save Shelf as Zip"
        panel.nameFieldStringValue = defaultExportFilename(ext: "zip")
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            store.exportAsZip(to: url) { result in
                handleExportResult(result)
            }
        }
    }

    private func exportAsFolder() {
        let panel = NSSavePanel()
        panel.title = "Save Shelf as Folder"
        panel.nameFieldStringValue = defaultExportFilename(ext: nil)
        panel.allowedContentTypes = [.folder]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            store.exportAsFolder(to: url) { result in
                handleExportResult(result)
            }
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .failure(let error):
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = (error as? FileStore.ExportError).map { _ in "There was nothing to export, or the destination couldn't be written." } ?? error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            Text("Shelf is empty")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Text("Drop a file here, or use the floating drop zone.\nIt appears automatically when you start dragging.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

struct FileTile: View {
    let item: ShelfItem
    let accent: Color
    @State private var hovering = false
    @ObservedObject private var store = FileStore.shared

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(hovering ? accent.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
                thumbnail
                    .frame(width: 92, height: 72)
            }
            .frame(height: 92)

            Text(item.name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(formatBytes(item.size))
                .font(.system(size: 9.5, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(hovering ? Color.white.opacity(0.04) : Color.clear)
        )
        .onHover { hovering = $0 }
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Open") { store.openItem(item) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Move to Trash", role: .destructive) { store.delete(item) }
        }
        .help(item.name)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let img = NSWorkspace.shared.icon(forFile: item.url.path) as NSImage? {
            Image(nsImage: previewImage(for: item) ?? img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: "doc")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func previewImage(for item: ShelfItem) -> NSImage? {
        if item.isImage, let img = NSImage(contentsOf: item.url) { return img }
        return nil
    }
}

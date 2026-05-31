import AppKit

/// Watches for file drags happening anywhere on the system.
/// Fires `onFileDragStart` when a file drag begins and `onDragEnd` on mouse up.
final class DragMonitor {
    static let shared = DragMonitor()

    var onFileDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?

    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var lastPasteboardChange: Int = -1
    private var isFileDragActive = false

    func start() {
        stop()

        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.handleDrag()
        }

        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.handleUp()
        }
    }

    func stop() {
        if let m = dragMonitor { NSEvent.removeMonitor(m); dragMonitor = nil }
        if let m = upMonitor { NSEvent.removeMonitor(m); upMonitor = nil }
    }

    private static let interestingTypes: Set<String> = [
        // Concrete file paths
        "public.file-url",
        "NSFilenamesPboardType",
        // File promises (e.g. screenshot thumbnails — the file doesn't exist yet)
        "com.apple.NSFilePromiseProvider",
        "com.apple.pasteboard.promised-file-url",
        "com.apple.pasteboard.promised-file-content-type",
        "com.apple.pasteboard.promised-file-name",
        "com.apple.pasteboard.promised-suggested-file-name",
        // Image / document data dragged out of apps
        "public.image", "public.png", "public.jpeg", "public.tiff",
        "public.heic", "public.heif",
        "public.pdf", "com.adobe.pdf",
        "public.movie", "public.mpeg-4", "com.apple.quicktime-movie",
    ]

    private func handleDrag() {
        guard !isFileDragActive else { return }
        let pb = NSPasteboard(name: .drag)
        if pb.changeCount == lastPasteboardChange { return }
        lastPasteboardChange = pb.changeCount

        let rawTypes = (pb.types ?? []).map { $0.rawValue }
        let hasInteresting = rawTypes.contains { Self.interestingTypes.contains($0) }

        if hasInteresting {
            isFileDragActive = true
            DispatchQueue.main.async { self.onFileDragStart?() }
        }
    }

    private func handleUp() {
        if isFileDragActive {
            isFileDragActive = false
            DispatchQueue.main.async { self.onDragEnd?() }
        }
    }
}

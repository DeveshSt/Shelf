import AppKit
import SwiftUI

/// Floating, borderless panel that appears at the chosen screen corner during drags.
final class DropWindowController {
    private let panel: NSPanel
    private var isVisible = false
    private var hideWorkItem: DispatchWorkItem?

    init() {
        let size = NSSize(width: 220, height: 220)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        let host = NSHostingView(rootView: DropZoneView())
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.alphaValue = 0.0
    }

    func show(animated: Bool = true) {
        cancelHide()
        repositionToCorner()
        if !isVisible {
            isVisible = true
            panel.orderFrontRegardless()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 1.0
            }
        } else {
            panel.alphaValue = 1.0
        }
    }

    func hide(animated: Bool = true) {
        cancelHide()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if animated {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.18
                    self.panel.animator().alphaValue = 0.0
                }, completionHandler: {
                    self.panel.orderOut(nil)
                    self.isVisible = false
                })
            } else {
                self.panel.alphaValue = 0.0
                self.panel.orderOut(nil)
                self.isVisible = false
            }
        }
        hideWorkItem = work
        let delay = SettingsStore.shared.autoHideSeconds
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func flashAcknowledge() {
        // Briefly bump scale/opacity to ack a successful drop.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 1.0
        }
    }

    private func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    func repositionToCorner() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let margin: CGFloat = 24
        let origin: NSPoint
        switch SettingsStore.shared.dropCorner {
        case .bottomLeft:
            origin = NSPoint(x: visible.minX + margin, y: visible.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.minY + margin)
        case .topLeft:
            origin = NSPoint(x: visible.minX + margin, y: visible.maxY - size.height - margin)
        case .topRight:
            origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin)
        case .bottomCenter:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + margin)
        }
        panel.setFrameOrigin(origin)
    }
}

// MARK: - SwiftUI drop zone view

struct DropZoneView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var store = FileStore.shared
    @State private var isTargeted = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Base
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(borderColor, lineWidth: isTargeted ? 2.5 : 1)
                )
                .overlay(
                    // Dashed inner outline
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            settings.accent.color.opacity(isTargeted ? 0.95 : 0.5),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                        )
                        .padding(10)
                )
                .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 10)

            VStack(spacing: 10) {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(settings.accent.color)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(isTargeted ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargeted)
                Text(isTargeted ? "Release to stash" : "Drop to Shelf")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                if store.items.count > 0 {
                    Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s") stashed")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(20)
        }
        .frame(width: 220, height: 220)
        .preferredColorScheme(.dark)
        .onDrop(of: [.fileURL, .image, .pdf, .movie, .item], isTargeted: $isTargeted) { providers in
            FileStore.shared.ingest(providers: providers)
            return true
        }
    }

    private var borderColor: Color {
        isTargeted ? settings.accent.color.opacity(0.9) : Color.white.opacity(0.12)
    }
}

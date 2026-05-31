import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let addedAt: Date
    let size: Int64

    var name: String { url.lastPathComponent }
    var isImage: Bool {
        let ext = url.pathExtension.lowercased()
        return ["png","jpg","jpeg","gif","heic","tiff","bmp","webp"].contains(ext)
    }
}

final class FileStore: ObservableObject {
    static let shared = FileStore()

    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var stagingDir: URL

    private static let stagingDirKey = "stagingDirBookmark"

    private var watcher: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1

    static var defaultStagingDir: URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        return desktop.appendingPathComponent("Shelf", isDirectory: true)
    }

    init() {
        if let path = UserDefaults.standard.string(forKey: Self.stagingDirKey), !path.isEmpty {
            self.stagingDir = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            self.stagingDir = Self.defaultStagingDir
        }
        ensureStagingDir()
        reload()
        startWatching()
    }

    deinit { stopWatching() }

    private func ensureStagingDir() {
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
    }

    // MARK: - Change folder

    enum ChangeFolderMode {
        case moveExisting
        case leaveExisting
    }

    /// Switch the staging folder. Returns true on success.
    @discardableResult
    func setStagingDir(_ newURL: URL, mode: ChangeFolderMode) -> Bool {
        let target = newURL.standardizedFileURL
        // Don't allow picking the exact same dir
        if target.path == stagingDir.path { return true }

        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            NSLog("Shelf: failed to create new staging dir: \(error)")
            return false
        }

        if mode == .moveExisting {
            let fm = FileManager.default
            if let contents = try? fm.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for url in contents {
                    var dest = target.appendingPathComponent(url.lastPathComponent)
                    var i = 2
                    while fm.fileExists(atPath: dest.path) {
                        let base = (url.lastPathComponent as NSString).deletingPathExtension
                        let ext = (url.lastPathComponent as NSString).pathExtension
                        let newName = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
                        dest = target.appendingPathComponent(newName)
                        i += 1
                    }
                    try? fm.moveItem(at: url, to: dest)
                }
            }
        }

        stopWatching()
        stagingDir = target
        UserDefaults.standard.set(target.path, forKey: Self.stagingDirKey)
        ensureStagingDir()
        reload()
        startWatching()
        return true
    }

    func resetStagingDirToDefault(mode: ChangeFolderMode) {
        setStagingDir(Self.defaultStagingDir, mode: mode)
    }

    // MARK: - Export

    enum ExportError: Error { case noFiles, coordinationFailed(String) }

    /// Zip the staging folder and write it to `destination`.
    func exportAsZip(to destination: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard !items.isEmpty else {
            completion(.failure(ExportError.noFiles)); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let coordinator = NSFileCoordinator()
            var coordError: NSError?
            var resultError: Error?
            var success = false
            coordinator.coordinate(readingItemAt: self.stagingDir, options: [.forUploading], error: &coordError) { tempZipURL in
                do {
                    let fm = FileManager.default
                    if fm.fileExists(atPath: destination.path) {
                        try fm.removeItem(at: destination)
                    }
                    try fm.copyItem(at: tempZipURL, to: destination)
                    success = true
                } catch {
                    resultError = error
                }
            }
            DispatchQueue.main.async {
                if success {
                    completion(.success(destination))
                } else if let err = resultError {
                    completion(.failure(err))
                } else if let err = coordError {
                    completion(.failure(ExportError.coordinationFailed(err.localizedDescription)))
                } else {
                    completion(.failure(ExportError.coordinationFailed("unknown")))
                }
            }
        }
    }

    /// Copy the staging folder (as a regular folder) to `destination`.
    func exportAsFolder(to destination: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard !items.isEmpty else {
            completion(.failure(ExportError.noFiles)); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fm = FileManager.default
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: self.stagingDir, to: destination)
                DispatchQueue.main.async { completion(.success(destination)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func reload() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .addedToDirectoryDateKey, .fileSizeKey, .isDirectoryKey]
        guard let contents = try? fm.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            items = []
            return
        }
        let mapped: [ShelfItem] = contents.compactMap { url in
            let r = try? url.resourceValues(forKeys: Set(keys))
            let date = r?.addedToDirectoryDate ?? r?.contentModificationDate ?? Date()
            let size = Int64(r?.fileSize ?? 0)
            return ShelfItem(url: url, addedAt: date, size: size)
        }
        items = mapped.sorted { $0.addedAt > $1.addedAt }
    }

    func ingest(urls: [URL], move: Bool = false) {
        ensureStagingDir()
        for src in urls {
            let dest = uniqueDestination(for: src.lastPathComponent)
            do {
                if move {
                    try FileManager.default.moveItem(at: src, to: dest)
                } else {
                    try FileManager.default.copyItem(at: src, to: dest)
                }
            } catch {
                NSLog("Shelf: failed to ingest \(src.path): \(error)")
            }
        }
        reload()
        NotificationCenter.default.post(name: .shelfFileDropped, object: nil)
    }

    // MARK: - Provider-based ingest (handles file promises like screenshot thumbnails)

    func ingest(providers: [NSItemProvider]) {
        for provider in providers {
            ingestOne(provider: provider)
        }
    }

    private func ingestOne(provider: NSItemProvider) {
        let types = provider.registeredTypeIdentifiers

        // 1. Existing file on disk — fastest, no copy from temp.
        if types.contains("public.file-url") {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let self, let u = url, u.isFileURL else { return }
                let dest = self.uniqueDestination(for: u.lastPathComponent)
                try? FileManager.default.copyItem(at: u, to: dest)
                DispatchQueue.main.async {
                    self.reload()
                    NotificationCenter.default.post(name: .shelfFileDropped, object: nil)
                }
            }
            return
        }

        // 2. File-promise / image data via file representation (covers screenshot thumbnails).
        let candidates: [String] = [
            "public.png", "public.jpeg", "public.tiff", "public.heic", "public.heif",
            "public.pdf", "com.adobe.pdf",
            "public.movie", "public.mpeg-4", "com.apple.quicktime-movie",
            "public.image",
            "public.plain-text", "public.utf8-plain-text",
        ]
        for type in candidates where types.contains(type) {
            provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] tempURL, _ in
                guard let self, let tempURL = tempURL else { return }
                let base = provider.suggestedName ?? "Stashed \(self.timestamp())"
                let ext = tempURL.pathExtension.isEmpty ? self.extensionForUTI(type) : tempURL.pathExtension
                let name = self.applyExtension(base, ext: ext)
                let dest = self.uniqueDestination(for: name)
                // The temp file is only valid inside this closure — copy synchronously.
                try? FileManager.default.copyItem(at: tempURL, to: dest)
                DispatchQueue.main.async {
                    self.reload()
                    NotificationCenter.default.post(name: .shelfFileDropped, object: nil)
                }
            }
            return
        }

        // 3. Last-resort: raw data of whatever the provider exposes first.
        if let firstType = types.first {
            provider.loadDataRepresentation(forTypeIdentifier: firstType) { [weak self] data, _ in
                guard let self, let data = data else { return }
                let base = provider.suggestedName ?? "Stashed \(self.timestamp())"
                let ext = self.extensionForUTI(firstType)
                let name = self.applyExtension(base, ext: ext)
                let dest = self.uniqueDestination(for: name)
                try? data.write(to: dest)
                DispatchQueue.main.async {
                    self.reload()
                    NotificationCenter.default.post(name: .shelfFileDropped, object: nil)
                }
            }
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: Date())
    }

    private func applyExtension(_ name: String, ext: String) -> String {
        let currentExt = (name as NSString).pathExtension.lowercased()
        if !currentExt.isEmpty && currentExt == ext.lowercased() { return name }
        let base = currentExt.isEmpty ? name : (name as NSString).deletingPathExtension
        return "\(base).\(ext)"
    }

    private func extensionForUTI(_ uti: String) -> String {
        switch uti {
        case "public.png":                                   return "png"
        case "public.jpeg", "public.jpg":                    return "jpg"
        case "public.tiff":                                  return "tiff"
        case "public.heic":                                  return "heic"
        case "public.heif":                                  return "heif"
        case "public.pdf", "com.adobe.pdf":                  return "pdf"
        case "public.movie", "public.mpeg-4":                return "mp4"
        case "com.apple.quicktime-movie":                    return "mov"
        case "public.mp3":                                   return "mp3"
        case "public.plain-text", "public.utf8-plain-text":  return "txt"
        case "public.image":                                 return "png"
        default:
            if let t = UTType(uti), let ext = t.preferredFilenameExtension { return ext }
            return "bin"
        }
    }

    private func uniqueDestination(for filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var attempt = stagingDir.appendingPathComponent(filename)
        var i = 2
        while FileManager.default.fileExists(atPath: attempt.path) {
            let newName = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            attempt = stagingDir.appendingPathComponent(newName)
            i += 1
        }
        return attempt
    }

    func delete(_ item: ShelfItem) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        reload()
    }

    func clearAll() {
        for item in items {
            try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        }
        reload()
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([stagingDir])
    }

    func openItem(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    // MARK: - Filesystem watch

    private func startWatching() {
        let fd = open(stagingDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { [weak self] in
            if let f = self?.watchedFD, f >= 0 { close(f) }
            self?.watchedFD = -1
        }
        source.resume()
        watcher = source
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }
}

func formatBytes(_ b: Int64) -> String {
    let f = ByteCountFormatter()
    f.allowedUnits = [.useKB, .useMB, .useGB]
    f.countStyle = .file
    return f.string(fromByteCount: b)
}

# Shelf

A little dropbox for short-term stuff on macOS. Drag screenshots and files into a
floating drop zone that pops up automatically whenever you start dragging, and
drag them back out whenever you need them.

Native macOS app, written in Swift + SwiftUI. ~1000 lines of code.

---

## What it does

- **Auto-popup drop zone.** The moment you start dragging a file (or a
  screenshot thumbnail) anywhere on the system, a small floating panel appears
  in the corner of your choice. Drop on it → file is stashed.
- **Handles screenshots.** Macs drag screenshot thumbnails as *file promises*
  rather than real files. Shelf understands those, plus normal file URLs, plus
  raw image/PDF/movie data dragged out of apps.
- **Drag back out.** Each tile in the main window is draggable into Finder,
  Mail, Slack, anywhere.
- **Configurable shelf folder.** Default is `~/Desktop/Shelf/`. Change it to
  wherever you want; existing files can be moved over or left in place.
- **Export.** Save the whole shelf as a zip or as a folder copy, ready to share.
- **Menu bar / Dock / Both.** Pick where Shelf lives. Switches live, no relaunch.
- **Launch at login.** Optional, uses the modern `SMAppService` API.
- **Theming.** 8 accent colors, 5 drop-zone corners.

## Requirements

- macOS 13 (Ventura) or newer

## Install (prebuilt — easiest)

1. Grab the latest **`Shelf-x.x.zip`** from [Releases](https://github.com/DeveshSt/Shelf/releases).
2. Unzip → drag `Shelf.app` into `/Applications`.
3. First launch: right-click → **Open** (since it's not notarized by Apple), confirm once.
4. From there on, Shelf checks for updates automatically and prompts you in-app
   when a new version is available.

## Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/DeveshSt/Shelf.git
cd Shelf
./build.sh
```

That compiles the Swift sources, downloads & embeds Sparkle, bundles
`Shelf.app`, ad-hoc signs it, and copies it to `/Applications`. To build
without installing:

```bash
INSTALL=0 ./build.sh
```

First launch opens the main window so you know it's alive; subsequent launches
go silently into the menu bar.

## Auto-updates

Shelf uses [Sparkle](https://sparkle-project.org) for in-app updates. On
launch it pings [`appcast.xml`](appcast.xml) on this repo, and if a newer
release is available it prompts you to install. EdDSA-signed; key generation
+ release flow is handled by [`release.sh`](release.sh).

## Project layout

```
Sources/
  ShelfApp.swift          @main entry
  AppDelegate.swift       presence policy, menu bar, drag wiring
  DragMonitor.swift       global file-drag detection
  DropWindow.swift        floating drop panel + SwiftUI view
  MainWindow.swift        main window controller
  MainContentView.swift   sidebar + file grid + export
  SettingsPane.swift      all settings UI
  FileStore.swift         staging folder, provider-based ingest, export
  SettingsStore.swift     UserDefaults prefs + SMAppService login item
Resources/
  AppIcon-source.png      master logo (icns is generated from this)
  AppIcon.icns            compiled app icon
Info.plist                bundle metadata (LSUIElement = true by default)
build.sh                  swiftc + bundle + ad-hoc sign + install
```

## How drags get detected

1. `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged)` fires
   whenever the user starts dragging.
2. We peek at `NSPasteboard(name: .drag)` and look for "interesting" types:
   file URLs, file promises (`com.apple.NSFilePromiseProvider`,
   `com.apple.pasteboard.promised-file-url`), image data, PDF data, etc.
3. If anything looks droppable, the floating drop panel fades in at the chosen
   corner. On `.leftMouseUp` it fades back out.

## How drops get ingested

For each `NSItemProvider`:
1. Try `loadObject(ofClass: URL.self)` for existing files.
2. Try `loadFileRepresentation(forTypeIdentifier:)` against a list of common
   UTIs — this fulfills file promises (screenshot thumbnails materialize here).
3. Fall back to `loadDataRepresentation(forTypeIdentifier:)` for raw bytes.

Files land in the staging folder, deduplicated by name.

## License

MIT — see [LICENSE](LICENSE).

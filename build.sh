#!/bin/bash
# Build Shelf.app — a native macOS Swift/SwiftUI app.
# Compiles Sources/*.swift, links Sparkle, assembles a .app bundle.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCES_DIR="$PROJECT_DIR/Sources"
RESOURCES_DIR="$PROJECT_DIR/Resources"
VENDOR_DIR="$PROJECT_DIR/vendor"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Shelf"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"
INSTALL=${INSTALL:-1}

# --- Sparkle bootstrap ---------------------------------------------------
SPARKLE_DIR="$VENDOR_DIR/sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_DIR/Sparkle.framework"

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "==> Sparkle not found; downloading latest"
    mkdir -p "$SPARKLE_DIR"
    LATEST_URL=$(curl -fsSL https://api.github.com/repos/sparkle-project/Sparkle/releases/latest \
        | grep "browser_download_url.*tar.xz" | head -1 \
        | sed -E 's/.*"(https[^"]+)".*/\1/')
    curl -fsSL "$LATEST_URL" -o "$VENDOR_DIR/sparkle.tar.xz"
    tar -xf "$VENDOR_DIR/sparkle.tar.xz" -C "$SPARKLE_DIR"
    rm -f "$VENDOR_DIR/sparkle.tar.xz"
fi

echo "==> Cleaning build dir"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" \
         "$APP_BUNDLE/Contents/Resources" \
         "$APP_BUNDLE/Contents/Frameworks"

echo "==> Compiling Swift sources"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SWIFT_FILES=("$SOURCES_DIR"/*.swift)

xcrun swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    -sdk "$SDK_PATH" \
    -F "$SPARKLE_DIR" \
    -framework AppKit \
    -framework SwiftUI \
    -framework UniformTypeIdentifiers \
    -framework Combine \
    -framework Sparkle \
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
    -parse-as-library \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "${SWIFT_FILES[@]}"

echo "==> Copying resources"
cp "$RESOURCES_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "==> Embedding Sparkle.framework"
cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"

echo "==> Ad-hoc signing (recursive)"
# Sign inner pieces first, then the bundle itself.
codesign --force --sign - --timestamp=none --options=runtime \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" 2>/dev/null || true
codesign --force --sign - --timestamp=none --options=runtime \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" 2>/dev/null || true
codesign --force --sign - --timestamp=none \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" 2>/dev/null || true
codesign --force --sign - --timestamp=none \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>/dev/null || true
codesign --force --sign - --timestamp=none \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
codesign --force --sign - --timestamp=none \
    "$APP_BUNDLE" 2>/dev/null || true

if [[ "$INSTALL" == "1" ]]; then
    echo "==> Installing to $INSTALL_DIR"
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
    echo "==> Installed: $INSTALL_DIR/$APP_NAME.app"
else
    echo "==> Built: $APP_BUNDLE  (set INSTALL=1 to install)"
fi

echo "==> Done."

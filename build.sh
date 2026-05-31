#!/bin/bash
# Build Shelf.app — a native macOS Swift/SwiftUI app.
# Compiles all Sources/*.swift, assembles a .app bundle, and (optionally) installs.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCES_DIR="$PROJECT_DIR/Sources"
RESOURCES_DIR="$PROJECT_DIR/Resources"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Shelf"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"
INSTALL=${INSTALL:-1}

echo "==> Cleaning build dir"
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

echo "==> Compiling Swift sources"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SWIFT_FILES=("$SOURCES_DIR"/*.swift)

xcrun swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    -sdk "$SDK_PATH" \
    -framework AppKit \
    -framework SwiftUI \
    -framework UniformTypeIdentifiers \
    -framework Combine \
    -parse-as-library \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "${SWIFT_FILES[@]}"

echo "==> Copying resources"
cp "$RESOURCES_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "==> Ad-hoc signing (lets app launch without quarantine flags)"
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

if [[ "$INSTALL" == "1" ]]; then
    echo "==> Installing to $INSTALL_DIR"
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
    echo "==> Installed: $INSTALL_DIR/$APP_NAME.app"
else
    echo "==> Built: $APP_BUNDLE  (set INSTALL=1 to install)"
fi

echo "==> Done."

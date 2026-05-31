#!/bin/bash
# Cut a new Shelf release.
#
#   ./release.sh 1.1            # version 1.1, build 2, auto-generated notes
#   ./release.sh 1.1 "Notes…"   # custom release notes (markdown OK)
#
# What this does, in order:
#   1. Bumps CFBundleShortVersionString + CFBundleVersion in Info.plist
#   2. Runs build.sh to produce a fresh Shelf.app (no install)
#   3. Zips it into build/Shelf-<version>.zip
#   4. Signs the zip with your Sparkle EdDSA private key (from Keychain)
#   5. Creates a GitHub Release tagged v<version> and uploads the zip
#   6. Prepends a <item> entry to appcast.xml with the signature
#   7. Commits + pushes Info.plist + appcast.xml

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <version> [release-notes-markdown]"
    echo "Example: $0 1.1 \"Fixes screenshot drag bug.\""
    exit 1
fi

VERSION="$1"
NOTES="${2:-Release ${VERSION}.}"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFO_PLIST="$PROJECT_DIR/Info.plist"
APPCAST="$PROJECT_DIR/appcast.xml"
BUILD_DIR="$PROJECT_DIR/build"
SIGN_TOOL="$PROJECT_DIR/vendor/sparkle/bin/sign_update"
APP_BUNDLE="$BUILD_DIR/Shelf.app"
ZIP_NAME="Shelf-${VERSION}.zip"
ZIP_PATH="$BUILD_DIR/$ZIP_NAME"
RELEASE_URL="https://github.com/DeveshSt/Shelf/releases/download/v${VERSION}/${ZIP_NAME}"

# --- 1. Bump version --------------------------------------------------------
echo "==> Bumping version to $VERSION"
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
NEXT_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$INFO_PLIST"
echo "    version=$VERSION  build=$NEXT_BUILD"

# --- 2. Build ---------------------------------------------------------------
echo "==> Building Shelf.app"
INSTALL=0 "$PROJECT_DIR/build.sh" >/dev/null

# --- 3. Zip -----------------------------------------------------------------
echo "==> Zipping app"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
ZIP_SIZE=$(stat -f%z "$ZIP_PATH")

# --- 4. Sign with Sparkle ---------------------------------------------------
echo "==> Signing zip with EdDSA key (may prompt the keychain on first run)"
SIGN_OUTPUT=$("$SIGN_TOOL" "$ZIP_PATH")
# Output looks like: sparkle:edSignature="…" length="…"
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -oE 'sparkle:edSignature="[^"]+"' | sed -E 's/.*="([^"]+)".*/\1/')
echo "    edSignature=${ED_SIGNATURE:0:24}…"

# --- 5. GitHub Release ------------------------------------------------------
echo "==> Creating GitHub release v$VERSION"
TAG="v${VERSION}"
gh release create "$TAG" "$ZIP_PATH" \
    --title "Shelf $VERSION" \
    --notes "$NOTES" \
    >/dev/null

# --- 6. Update appcast.xml --------------------------------------------------
echo "==> Updating appcast.xml"
PUB_DATE=$(LC_ALL=en_US.UTF-8 date "+%a, %d %b %Y %H:%M:%S %z")
HTML_NOTES=$(printf '%s' "$NOTES" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

ITEM=$(cat <<EOF
        <item>
            <title>Shelf ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${NEXT_BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <description><![CDATA[${HTML_NOTES}]]></description>
            <enclosure
                url="${RELEASE_URL}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${ZIP_SIZE}"
                type="application/octet-stream"/>
        </item>
EOF
)

# Prepend the new <item> right before the <!-- RELEASE_ITEMS --> marker.
APPCAST_PATH="$APPCAST" NEW_ITEM="$ITEM" python3 <<'PY'
import os
path = os.environ["APPCAST_PATH"]
item = os.environ["NEW_ITEM"]
marker = "<!-- RELEASE_ITEMS -->"
with open(path) as f:
    contents = f.read()
contents = contents.replace(marker, item + "\n        " + marker)
with open(path, "w") as f:
    f.write(contents)
PY

# --- 7. Commit + push -------------------------------------------------------
echo "==> Committing + pushing"
git add Info.plist appcast.xml
git commit -m "Release v${VERSION}" >/dev/null
git push origin main >/dev/null

echo
echo "==> Done."
echo "    Release:  https://github.com/DeveshSt/Shelf/releases/tag/${TAG}"
echo "    Appcast:  https://raw.githubusercontent.com/DeveshSt/Shelf/main/appcast.xml"
echo "    Zip:      ${RELEASE_URL}"

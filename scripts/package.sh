#!/usr/bin/env bash
#
# Build a Release "Delta Diff.app", ad-hoc sign it, and package it as a zip
# for distribution via GitHub Releases.
#
# The app is not notarized, so users clear the quarantine attribute on first
# launch (see README's "Install" section). Ad-hoc signing is still applied so
# the binary runs on Apple Silicon and avoids "app is damaged" false positives.
#
# Usage:  scripts/package.sh
# Output: dist/Delta-Diff.zip
set -euo pipefail

cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

DERIVED="build-release"
DIST="dist"
# The product/target is internally "Delta" (Delta.app); the display name is
# "Delta Diff". For distribution we rename the bundle to match the display name
# so the app and the README's quarantine path read "Delta Diff.app".
BUILT_APP="$DERIVED/Build/Products/Release/Delta.app"
DIST_APP="$DIST/Delta Diff.app"
ZIP_NAME="Delta-Diff.zip"

echo "==> Generating Xcode project (xcodegen)"
xcodegen generate

echo "==> Building Release"
xcodebuild -project Delta.xcodeproj -scheme Delta -configuration Release \
  -derivedDataPath "$DERIVED" build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: built app not found at: $BUILT_APP" >&2
  exit 1
fi

echo "==> Staging as 'Delta Diff.app'"
mkdir -p "$DIST"
rm -rf "$DIST_APP"
cp -R "$BUILT_APP" "$DIST_APP"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$DIST_APP"
codesign --verify --deep --strict "$DIST_APP"

echo "==> Packaging zip"
rm -f "$DIST/$ZIP_NAME"
# ditto preserves the bundle structure correctly for distribution.
ditto -c -k --sequesterRsrc --keepParent "$DIST_APP" "$DIST/$ZIP_NAME"
rm -rf "$DIST_APP"

echo "==> Done: $DIST/$ZIP_NAME"

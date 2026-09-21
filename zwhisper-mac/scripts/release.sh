#!/bin/bash
set -euo pipefail

# End-to-end release: test -> build -> sign -> .dmg -> notarize -> staple ->
# signed Sparkle appcast -> GitHub release.
#
# Prereqs:
#   - Release signing config in project.yml (Developer ID, Team 5JJ6G6A84S,
#     hardened runtime, audio-input entitlement).
#   - scripts/.notary-config.local (App Store Connect API key; gitignored).
#   - Sparkle EdDSA key in the keychain (SUPublicEDKey in project.yml matches it).
#
# Usage: scripts/release.sh 1.0.0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
VERSION="${1:?usage: release.sh <version>  e.g. 1.0.0}"
APP_NAME="zWhisper"
APP_DIR="$ROOT/build/$APP_NAME.app"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"
DIST="$ROOT/build/dist"
DOWNLOAD_URL_PREFIX="https://github.com/umzcio/zWhisper/releases/download/v$VERSION/"
SPARKLE_BIN="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin"

echo "==> [1/6] Run the test suite"
xcodebuild -project "$ROOT/zWhisper.xcodeproj" -scheme "$APP_NAME" -configuration Debug \
    -destination 'platform=macOS' \
    -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" \
    CODE_SIGNING_ALLOWED=NO \
    test

echo "==> [2/6] Build + sign app"
bash "$ROOT/scripts/build-app.sh"

BUILT_VERSION="$(defaults read "$APP_DIR/Contents/Info" CFBundleShortVersionString)"
if [ "$BUILT_VERSION" != "$VERSION" ]; then
  echo "error: built app is $BUILT_VERSION but release.sh was invoked for $VERSION." >&2
  echo "       Bump MARKETING_VERSION in project.yml and commit first." >&2
  exit 1
fi

echo "==> [3/6] Package + notarize the .dmg"
bash "$ROOT/scripts/make-dmg.sh" "$VERSION"
bash "$ROOT/scripts/notarize.sh" "$DMG"

echo "==> [4/6] Staple the .app, then repackage so the shipped app carries its ticket"
xcrun stapler staple "$APP_DIR"
bash "$ROOT/scripts/make-dmg.sh" "$VERSION"
# The repackaged dmg is a new file, so it needs its own notarization + staple.
bash "$ROOT/scripts/notarize.sh" "$DMG"

echo "==> [5/6] Generate the signed Sparkle appcast"
rm -rf "$DIST"; mkdir -p "$DIST"
cp "$DMG" "$DIST/"
"$SPARKLE_BIN/generate_appcast" "$DIST" --download-url-prefix "$DOWNLOAD_URL_PREFIX"
cp "$DIST/appcast.xml" "$REPO_ROOT/appcast.xml"

echo "==> [6/6] Create the GitHub release"
gh release create "v$VERSION" "$DMG" \
    --repo umzcio/zWhisper \
    --title "zWhisper $VERSION" \
    --generate-notes

echo
echo "  DMG     : $DMG"
echo "  appcast : $REPO_ROOT/appcast.xml"
echo
echo "  Next: git add appcast.xml && git commit -m \"appcast: $VERSION\" && git push"

#!/bin/bash
set -euo pipefail

# Notarizes a .dmg / .zip / .app with Apple using an App Store Connect API key,
# then staples the ticket. Credentials come from scripts/.notary-config.local
# (gitignored; same setup as Fiddle's scripts/.notary-config.local).
#
# Usage: scripts/notarize.sh build/zWhisper-1.0.0.dmg
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT="${1:?usage: notarize.sh <path-to-dmg-zip-or-app>}"
CONFIG="$ROOT/scripts/.notary-config.local"

[ -f "$CONFIG" ] || { echo "error: $CONFIG not found"; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG"
KEY_PATH="${NOTARY_KEY/#\~/$HOME}"

echo "==> Submitting $(basename "$ARTIFACT") to Apple notary"
xcrun notarytool submit "$ARTIFACT" \
    --key "$KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" \
    --wait

echo "==> Stapling"
xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$ARTIFACT"
echo "==> Notarized + stapled: $ARTIFACT"

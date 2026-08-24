#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"

APP_NAME="${APP_NAME:-Minecraft Bedrock Launcher}"
APP_VERSION="${APP_VERSION:-0.1.0}"
OUT_DIR="${OUT_DIR:-$PACKAGE_DIR/.build/dmg}"
APP_PATH="${APP_PATH:-}"
DMG_NAME="${DMG_NAME:-$APP_NAME-$APP_VERSION.dmg}"
DMG_PATH="$OUT_DIR/$DMG_NAME"

NOTARY_PROFILE="${NOTARY_PROFILE:-}"

mkdir -p "$OUT_DIR"

if [[ -z "$APP_PATH" ]]; then
  APP_OUTPUT="$("$SCRIPT_DIR/build-app-bundle.sh")"
  echo "$APP_OUTPUT"
  APP_PATH="$(echo "$APP_OUTPUT" | tail -n 1)"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle was not found: $APP_PATH" >&2
  exit 1
fi

if [[ "$APP_PATH:t" != *.app ]]; then
  echo "error: APP_PATH must point to a .app bundle: $APP_PATH" >&2
  exit 1
fi

STAGING_DIR="$OUT_DIR/staging"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

ditto "$APP_PATH" "$STAGING_DIR/$APP_PATH:t"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -srcfolder "$STAGING_DIR" \
  -volname "$APP_NAME" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"
echo "$DMG_PATH"

#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"

APP_NAME="${APP_NAME:-Minecraft Bedrock Launcher}"
APP_VERSION="${APP_VERSION:-0.1.0}"
OUT_DIR="${OUT_DIR:-$PACKAGE_DIR/.build/dmg}"
APP_BUILD_DIR="${APP_BUILD_DIR:-$PACKAGE_DIR/.build/app}"
APP_PATH="${APP_PATH:-}"
DMG_NAME="${DMG_NAME:-$APP_NAME-$APP_VERSION.dmg}"
DMG_PATH="${DMG_PATH:-$OUT_DIR/$DMG_NAME}"
VOLUME_NAME="${VOLUME_NAME:-$APP_NAME}"
BACKGROUND_IMAGE="${BACKGROUND_IMAGE:-$PACKAGE_DIR/Resources/back.png}"

DMG_WINDOW_WIDTH="${DMG_WINDOW_WIDTH:-600}"
DMG_WINDOW_HEIGHT="${DMG_WINDOW_HEIGHT:-400}"
DMG_ICON_SIZE="${DMG_ICON_SIZE:-96}"
DMG_APP_ICON_X="${DMG_APP_ICON_X:-150}"
DMG_APP_ICON_Y="${DMG_APP_ICON_Y:-170}"
DMG_APPLICATIONS_ICON_X="${DMG_APPLICATIONS_ICON_X:-375}"
DMG_APPLICATIONS_ICON_Y="${DMG_APPLICATIONS_ICON_Y:-285}"

NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_APPLE_ID="${NOTARY_APPLE_ID:-}"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-}"
NOTARY_PASSWORD="${NOTARY_PASSWORD:-}"
NOTARIZE_DMG="${NOTARIZE_DMG:-}"

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
RW_DMG="$OUT_DIR/$APP_NAME-$APP_VERSION.rw.dmg"

rm -rf "$STAGING_DIR" "$RW_DMG" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

ditto "$APP_PATH" "$STAGING_DIR/$APP_PATH:t"
ln -s /Applications "$STAGING_DIR/Applications"

if [[ -f "$BACKGROUND_IMAGE" ]]; then
  mkdir -p "$STAGING_DIR/.background"
  cp "$BACKGROUND_IMAGE" "$STAGING_DIR/.background/background.png"
else
  echo "warning: DMG background image was not found: $BACKGROUND_IMAGE" >&2
fi

hdiutil create \
  -srcfolder "$STAGING_DIR" \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -size 200m \
  "$RW_DMG" >/dev/null

MOUNT_OUTPUT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
DEVICE="$(echo "$MOUNT_OUTPUT" | awk '/Apple_HFS/ { print $1; exit }')"
MOUNT_DIR="$(echo "$MOUNT_OUTPUT" | awk '/Apple_HFS/ { for (i = 3; i <= NF; i++) { if (i > 3) printf " "; printf $i } print ""; exit }')"

if [[ -z "$DEVICE" || -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
  echo "error: failed to mount writable DMG" >&2
  exit 1
fi

cleanup() {
  hdiutil detach "$DEVICE" -quiet 2>/dev/null || true
}
trap cleanup EXIT

if [[ -f "$MOUNT_DIR/.background/background.png" ]]; then
  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 100 + $DMG_WINDOW_WIDTH, 100 + $DMG_WINDOW_HEIGHT}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $DMG_ICON_SIZE
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$APP_PATH:t" of container window to {$DMG_APP_ICON_X, $DMG_APP_ICON_Y}
    set position of item "Applications" of container window to {$DMG_APPLICATIONS_ICON_X, $DMG_APPLICATIONS_ICON_Y}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
fi

sync
hdiutil detach "$DEVICE" -quiet
trap - EXIT

hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR" "$RW_DMG"

if [[ -n "$NOTARY_PROFILE" || -n "$NOTARY_APPLE_ID" || -n "$NOTARIZE_DMG" ]]; then
  if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$DMG_PATH" \
      --keychain-profile "$NOTARY_PROFILE" \
      --wait
  else
    if [[ -z "$NOTARY_APPLE_ID" || -z "$NOTARY_TEAM_ID" || -z "$NOTARY_PASSWORD" ]]; then
      echo "error: set NOTARY_PROFILE or NOTARY_APPLE_ID, NOTARY_TEAM_ID, and NOTARY_PASSWORD to notarize" >&2
      exit 1
    fi
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$NOTARY_APPLE_ID" \
      --team-id "$NOTARY_TEAM_ID" \
      --password "$NOTARY_PASSWORD" \
      --wait
  fi

  xcrun stapler staple "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"
echo "$DMG_PATH"

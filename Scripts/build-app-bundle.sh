#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="${APP_NAME:-Minecraft Bedrock Launcher}"
APP_VERSION="${APP_VERSION:-0.1.0}"
OUT_DIR="${OUT_DIR:-$PACKAGE_DIR/.build/app}"
APP_DIR="$OUT_DIR/$APP_NAME.app"
EXECUTABLE_NAME="MinecraftBedrockLauncher"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
APP_ICON_DOCUMENT="${APP_ICON_DOCUMENT:-$PACKAGE_DIR/Resources/minecraft-bedrock.icon}"
APP_ICON_NAME="${APP_ICON_NAME:-${APP_ICON_DOCUMENT:t:r}}"
ACTOOL="${ACTOOL:-$(xcrun --find actool 2>/dev/null || true)}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-14.0}"

mkdir -p "$OUT_DIR"
rm -rf "$APP_DIR"

swift build \
  --package-path "$PACKAGE_DIR" \
  -c "$CONFIGURATION" \
  --product MinecraftBedrockLauncher

swift build \
  --package-path "$PACKAGE_DIR" \
  -c "$CONFIGURATION" \
  --product mcpelauncher-ui-qt

swift build \
  --package-path "$PACKAGE_DIR" \
  -c "$CONFIGURATION" \
  --product mcpelauncher-webview

BUILD_DIR="$(swift build --package-path "$PACKAGE_DIR" -c "$CONFIGURATION" --show-bin-path)"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Helpers"
mkdir -p "$APP_DIR/Contents/Frameworks"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/Resources/Licenses"

if [[ ! -d "$APP_ICON_DOCUMENT" ]]; then
  echo "error: app icon document was not found: $APP_ICON_DOCUMENT" >&2
  exit 1
fi

ICON_WORK_DIR="$PACKAGE_DIR/.build/icon"
ICON_COMPILE_DIR="$ICON_WORK_DIR/compiled"
ICON_PARTIAL_INFO_PLIST="$ICON_COMPILE_DIR/assetcatalog_generated_info.plist"
rm -rf "$ICON_COMPILE_DIR"
mkdir -p "$ICON_COMPILE_DIR"

if [[ ! -x "$ACTOOL" ]]; then
  echo "error: Xcode actool was not found. Icon Composer app icons require Xcode 26 or newer." >&2
  exit 1
fi

"$ACTOOL" "$APP_ICON_DOCUMENT" \
  --app-icon "$APP_ICON_NAME" \
  --compile "$ICON_COMPILE_DIR" \
  --output-partial-info-plist "$ICON_PARTIAL_INFO_PLIST" \
  --minimum-deployment-target "$MACOS_DEPLOYMENT_TARGET" \
  --platform macosx \
  --target-device mac >/dev/null

if [[ ! -f "$ICON_COMPILE_DIR/Assets.car" || ! -f "$ICON_COMPILE_DIR/$APP_ICON_NAME.icns" ]]; then
  echo "error: actool did not produce Assets.car and $APP_ICON_NAME.icns for $APP_ICON_DOCUMENT" >&2
  exit 1
fi

cp "$ICON_COMPILE_DIR/Assets.car" "$APP_DIR/Contents/Resources/Assets.car"
cp "$ICON_COMPILE_DIR/$APP_ICON_NAME.icns" "$APP_DIR/Contents/Resources/$APP_ICON_NAME.icns"
cp "$PACKAGE_DIR/Resources/cut-bedrock-launcher-icon-foreground-transparent.png" "$APP_DIR/Contents/Resources/cut-bedrock-launcher-icon-foreground-transparent.png"
cp "$PACKAGE_DIR/Resources/ThirdPartyNotices.txt" "$APP_DIR/Contents/Resources/ThirdPartyNotices.txt"
cp "$PACKAGE_DIR/LICENSE" "$APP_DIR/Contents/Resources/Licenses/Minecraft-Bedrock-Launcher-MIT.txt"

cp "$BUILD_DIR/MinecraftBedrockLauncher" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod 755 "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME" 2>/dev/null || true
for resource_bundle in "$BUILD_DIR"/*.bundle(N); do
  [[ -d "$resource_bundle" ]] || continue
  ditto "$resource_bundle" "$APP_DIR/Contents/Resources/${resource_bundle:t}"
done
cp "$BUILD_DIR/mcpelauncher-ui-qt" "$APP_DIR/Contents/Helpers/mcpelauncher-ui-qt"
chmod 755 "$APP_DIR/Contents/Helpers/mcpelauncher-ui-qt"
cp "$BUILD_DIR/mcpelauncher-webview" "$APP_DIR/Contents/Helpers/mcpelauncher-webview"
chmod 755 "$APP_DIR/Contents/Helpers/mcpelauncher-webview"

SPARKLE_FRAMEWORK="$(find "$PACKAGE_DIR/.build" -path "*/Sparkle.framework" -type d -print -quit)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "error: Sparkle.framework was not found after swift build" >&2
  exit 1
fi
ditto "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
SPARKLE_LICENSE="$(find "$PACKAGE_DIR/.build/checkouts/Sparkle" -maxdepth 2 -name LICENSE -type f -print -quit 2>/dev/null || true)"
if [[ -n "$SPARKLE_LICENSE" ]]; then
  cp "$SPARKLE_LICENSE" "$APP_DIR/Contents/Resources/Licenses/Sparkle-LICENSE.txt"
fi

if [[ -n "${GPLAYVER_PATH:-}" || -n "${GPLAYDL_PATH:-}" ]]; then
  if [[ -z "${GPLAYVER_PATH:-}" || -z "${GPLAYDL_PATH:-}" ]]; then
    echo "error: set both GPLAYVER_PATH=/path/to/gplayver and GPLAYDL_PATH=/path/to/gplaydl" >&2
    exit 1
  fi
  cp "$GPLAYVER_PATH" "$APP_DIR/Contents/Helpers/gplayver"
  cp "$GPLAYDL_PATH" "$APP_DIR/Contents/Helpers/gplaydl"
  chmod 755 "$APP_DIR/Contents/Helpers/gplayver"
  chmod 755 "$APP_DIR/Contents/Helpers/gplaydl"
else
  GOOGLE_PLAY_TOOLS_OUTPUT="$("$SCRIPT_DIR/build-google-play-tools.sh")"
  echo "$GOOGLE_PLAY_TOOLS_OUTPUT"
  GPLAYVER_PATH="$(echo "$GOOGLE_PLAY_TOOLS_OUTPUT" | tail -n 2 | sed -n '1p')"
  GPLAYDL_PATH="$(echo "$GOOGLE_PLAY_TOOLS_OUTPUT" | tail -n 1)"
  if [[ ! -x "$GPLAYVER_PATH" || ! -x "$GPLAYDL_PATH" ]]; then
    echo "error: failed to build gplayver and gplaydl; set GPLAYVER_PATH and GPLAYDL_PATH manually" >&2
    exit 1
  fi
  cp "$GPLAYVER_PATH" "$APP_DIR/Contents/Helpers/gplayver"
  cp "$GPLAYDL_PATH" "$APP_DIR/Contents/Helpers/gplaydl"
  chmod 755 "$APP_DIR/Contents/Helpers/gplayver"
  chmod 755 "$APP_DIR/Contents/Helpers/gplaydl"
fi

GOOGLE_PLAY_API_LICENSE="$(find "$PACKAGE_DIR/.build/google-play-api" "$PACKAGE_DIR/.build/google-play-api-patched" -maxdepth 1 -name LICENSE -type f -print -quit 2>/dev/null || true)"
if [[ -n "$GOOGLE_PLAY_API_LICENSE" ]]; then
  cp "$GOOGLE_PLAY_API_LICENSE" "$APP_DIR/Contents/Resources/Licenses/Google-Play-API-LICENSE.txt"
fi
GOOGLE_PLAY_API_NOTICE="$(find "$PACKAGE_DIR/.build/google-play-api" "$PACKAGE_DIR/.build/google-play-api-patched" -maxdepth 1 -name NOTICE -type f -print -quit 2>/dev/null || true)"
if [[ -n "$GOOGLE_PLAY_API_NOTICE" ]]; then
  cp "$GOOGLE_PLAY_API_NOTICE" "$APP_DIR/Contents/Resources/Licenses/Google-Play-API-NOTICE.txt"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>local.minecraft.bedrock.swiftlauncher</string>
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME</string>
  <key>CFBundleIconName</key>
  <string>$APP_ICON_NAME</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.games</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSSupportsGameMode</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if [[ -n "$SPARKLE_FEED_URL" || -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  if [[ -z "$SPARKLE_FEED_URL" || -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "error: set both SPARKLE_FEED_URL and SPARKLE_PUBLIC_ED_KEY to enable app updates" >&2
    exit 1
  fi
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 86400" "$APP_DIR/Contents/Info.plist"
fi

plutil -lint "$APP_DIR/Contents/Info.plist"

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR"
elif [[ "$CODESIGN_IDENTITY" != "skip" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi

echo "$APP_DIR"

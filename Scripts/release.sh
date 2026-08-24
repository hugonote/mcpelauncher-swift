#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"
cd "$PACKAGE_DIR"

: "${SPARKLE_PUBLIC_ED_KEY:?Missing SPARKLE_PUBLIC_ED_KEY}"
: "${SPARKLE_PRIVATE_ED_KEY:?Missing SPARKLE_PRIVATE_ED_KEY}"

[[ "$GITHUB_REF_NAME" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]] || {
  echo "error: invalid release tag: $GITHUB_REF_NAME" >&2
  exit 1
}

APP_NAME="${APP_NAME:-Minecraft Bedrock Launcher}"
APP_VERSION="${GITHUB_REF_NAME#v}"
DMG_NAME="${APP_NAME// /.}-$APP_VERSION.dmg"
RELEASE_NOTES="ReleaseNotes/$GITHUB_REF_NAME.md"
RELEASE_DIR="$PACKAGE_DIR/.build/release"
DOWNLOAD_URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$GITHUB_REF_NAME/$DMG_NAME"

test -f "$RELEASE_NOTES"
export APP_NAME APP_VERSION DMG_NAME
"$SCRIPT_DIR/build-dmg.sh"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
cp ".build/dmg/$DMG_NAME" "$RELEASE_DIR/"
cp "$RELEASE_NOTES" "$RELEASE_DIR/${DMG_NAME%.dmg}.md"

printf '%s' "$SPARKLE_PRIVATE_ED_KEY" | \
  .build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --ed-key-file - \
    --download-url-prefix "${DOWNLOAD_URL%/*}/" \
    --embed-release-notes \
    --maximum-deltas 0 \
    "$RELEASE_DIR"

grep -F "$DOWNLOAD_URL" "$RELEASE_DIR/appcast.xml"
grep -F 'sparkle:edSignature=' "$RELEASE_DIR/appcast.xml"
codesign --verify --deep --strict ".build/app/$APP_NAME.app"

NOTES="$RELEASE_DIR/${DMG_NAME%.dmg}.md"
if gh release view "$GITHUB_REF_NAME" >/dev/null 2>&1; then
  gh release upload "$GITHUB_REF_NAME" "$RELEASE_DIR/$DMG_NAME" "$RELEASE_DIR/appcast.xml" --clobber
  gh release edit "$GITHUB_REF_NAME" --notes-file "$NOTES"
else
  gh release create "$GITHUB_REF_NAME" "$RELEASE_DIR/$DMG_NAME" "$RELEASE_DIR/appcast.xml" \
    --verify-tag \
    --title "$GITHUB_REF_NAME" \
    --notes-file "$NOTES"
fi

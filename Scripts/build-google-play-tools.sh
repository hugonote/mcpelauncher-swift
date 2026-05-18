#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"
GOOGLE_PLAY_API_URL="${GOOGLE_PLAY_API_URL:-https://github.com/minecraft-linux/Google-Play-API.git}"
GOOGLE_PLAY_API_REF="${GOOGLE_PLAY_API_REF:-master}"

if [[ -n "${GOOGLE_PLAY_API_SOURCE:-}" ]]; then
  SOURCE_DIR="$GOOGLE_PLAY_API_SOURCE"
  MANAGED_SOURCE=false
elif [[ -d "$PACKAGE_DIR/../mcpelauncher-ui-manifest/google-play-api" ]]; then
  SOURCE_DIR="$PACKAGE_DIR/../mcpelauncher-ui-manifest/google-play-api"
  MANAGED_SOURCE=false
else
  SOURCE_DIR="$PACKAGE_DIR/.build/google-play-api"
  MANAGED_SOURCE=true
fi

BUILD_DIR="${GOOGLE_PLAY_API_BUILD_DIR:-$PACKAGE_DIR/.build/google-play-api-build}"
PATCHED_SOURCE_DIR="${GOOGLE_PLAY_API_PATCHED_SOURCE_DIR:-$PACKAGE_DIR/.build/google-play-api-patched}"
PATCH_FILE="$PACKAGE_DIR/Scripts/patches/google-play-api-gplaydl-aggregate-progress.patch"
CMAKE_GENERATOR="${CMAKE_GENERATOR:-Unix Makefiles}"
CMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  mkdir -p "${SOURCE_DIR:h}"
  git clone --depth 1 --branch "$GOOGLE_PLAY_API_REF" "$GOOGLE_PLAY_API_URL" "$SOURCE_DIR"
elif [[ "$MANAGED_SOURCE" == true ]]; then
  git -C "$SOURCE_DIR" fetch --depth 1 origin "$GOOGLE_PLAY_API_REF"
  git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD
fi

rm -rf "$PATCHED_SOURCE_DIR"
ditto "$SOURCE_DIR" "$PATCHED_SOURCE_DIR"
git -C "$PATCHED_SOURCE_DIR" apply "$PATCH_FILE"
SOURCE_DIR="$PATCHED_SOURCE_DIR"

rm -rf "$BUILD_DIR"
cmake \
  -S "$SOURCE_DIR" \
  -B "$BUILD_DIR" \
  -G "$CMAKE_GENERATOR" \
  -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE"

cmake --build "$BUILD_DIR" --target gplayver gplaydl

echo "$BUILD_DIR/gplayver"
echo "$BUILD_DIR/gplaydl"

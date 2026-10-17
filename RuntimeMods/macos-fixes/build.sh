#!/bin/zsh
set -euo pipefail

MOD_DIR="${0:A:h}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-/opt/homebrew/share/android-ndk}}"
OUTPUT_DIR="${1:-$MOD_DIR/build/out}"

if [[ ! -f "$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" ]]; then
  echo "error: Android NDK not found at $ANDROID_NDK_HOME (set ANDROID_NDK_HOME)" >&2
  exit 1
fi

GENERATOR=()
if command -v ninja > /dev/null; then
  GENERATOR=(-G Ninja)
fi

cmake -S "$MOD_DIR" -B "$MOD_DIR/build" "${GENERATOR[@]}" \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=Release > /dev/null
cmake --build "$MOD_DIR/build" > /dev/null

mkdir -p "$OUTPUT_DIR/arm64-v8a"
install -m 755 "$MOD_DIR/build/arm64-v8a/libmacos_fixes.so" "$OUTPUT_DIR/arm64-v8a/libmacos_fixes.so"
echo "$OUTPUT_DIR/arm64-v8a/libmacos_fixes.so"

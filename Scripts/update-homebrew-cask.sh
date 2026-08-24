#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
TAP_DIR="$PACKAGE_DIR/homebrew-tap"
CASK="$TAP_DIR/Casks/minecraft-bedrock-launcher.rb"

VERSION="${GITHUB_REF_NAME#v}"
DMG_NAME="Minecraft.Bedrock.Launcher-$VERSION.dmg"
DIGEST="$(gh api "repos/$GITHUB_REPOSITORY/releases/tags/$GITHUB_REF_NAME" \
  --jq ".assets[] | select(.name == \"$DMG_NAME\") | .digest")"
[[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || {
  echo "error: missing digest for $DMG_NAME" >&2
  exit 1
}

ruby - "$CASK" "$VERSION" "${DIGEST#sha256:}" <<'RUBY'
path, version, sha256 = ARGV
text = File.read(path)
abort "version stanza not found" unless text.sub!(/version "[^"]+"/, %(version "#{version}"))
abort "sha256 stanza not found" unless text.sub!(/sha256 "[0-9a-f]{64}"/, %(sha256 "#{sha256}"))
File.write(path, text)
RUBY

git -C "$TAP_DIR" diff --quiet -- Casks/minecraft-bedrock-launcher.rb && exit 0
git -C "$TAP_DIR" config user.name "github-actions[bot]"
git -C "$TAP_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$TAP_DIR" add Casks/minecraft-bedrock-launcher.rb
git -C "$TAP_DIR" commit -m "minecraft-bedrock-launcher $GITHUB_REF_NAME"
git -C "$TAP_DIR" push

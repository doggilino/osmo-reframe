#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/build/shaders"
MODULE_CACHE="$OUTPUT_DIR/ModuleCache"
SOURCE="$ROOT/FxPlug/OsmoReframeShaders.metal"
AIR="$OUTPUT_DIR/OsmoReframe.air"
LIBRARY="$OUTPUT_DIR/OsmoReframe.metallib"

METAL_COMPILER=""
for CANDIDATE in /var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain-*/Metal.xctoolchain/usr/bin/metal; do
  if [[ -x "$CANDIDATE" ]]; then
    METAL_COMPILER="$CANDIDATE"
    break
  fi
done
if [[ -z "$METAL_COMPILER" ]]; then
  METAL_COMPILER="$(xcrun --find metal 2>/dev/null || true)"
fi
METALLIB_COMPILER="${METAL_COMPILER%/metal}/metallib"
if [[ ! -x "$METAL_COMPILER" || ! -x "$METALLIB_COMPILER" ]]; then
  echo "Metal toolchain is missing. Run: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$MODULE_CACHE"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
"$METAL_COMPILER" \
  -c \
  -target air64-apple-macos13.0 \
  -isysroot "$SDK_PATH" \
  -fmodules-cache-path="$MODULE_CACHE" \
  "$SOURCE" \
  -o "$AIR"
"$METALLIB_COMPILER" "$AIR" -o "$LIBRARY"

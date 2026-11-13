#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/build/tests/shader-smoke"

"$ROOT/scripts/build-shaders.sh"
mkdir -p "$(dirname "$OUTPUT")"
xcrun clang++ \
  -std=c++17 \
  -fobjc-arc \
  -framework Foundation \
  -framework Metal \
  "$ROOT/Tests/ShaderSmoke/main.mm" \
  -o "$OUTPUT"
"$OUTPUT" "$ROOT/build/shaders/OsmoReframe.metallib"


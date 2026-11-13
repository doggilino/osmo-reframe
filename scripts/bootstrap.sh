#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required (brew install xcodegen)." >&2
  exit 1
fi

if [[ ! -d /Library/Developer/SDKs/FxPlug.sdk ]]; then
  echo "FxPlug SDK not found at /Library/Developer/SDKs/FxPlug.sdk." >&2
  exit 1
fi

"$ROOT/scripts/build-shaders.sh"

cd "$ROOT"
xcodegen generate

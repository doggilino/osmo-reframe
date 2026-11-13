#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/bootstrap.sh"
xcodebuild \
  -project "$ROOT/OsmoReframe.xcodeproj" \
  -scheme OsmoReframe \
  -configuration Release \
  -derivedDataPath "$ROOT/DerivedData" \
  build

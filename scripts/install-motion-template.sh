#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/MotionTemplate/OsmoReframe"
DESTINATION="$HOME/Movies/Motion Templates.localized/Effects.localized/360/OsmoReframe"

mkdir -p "$(dirname "$DESTINATION")"
rm -rf "$DESTINATION"
ditto "$SOURCE" "$DESTINATION"
echo "Installed $DESTINATION"


#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/DerivedData"

"$ROOT/scripts/build.sh"

APP="$DERIVED/Build/Products/Release/OsmoReframe.app"
DESTINATION="$HOME/Applications/OsmoReframe.app"
mkdir -p "$HOME/Applications"
rm -rf "$DESTINATION"
ditto "$APP" "$DESTINATION"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f -R -trusted "$DESTINATION"
"$ROOT/scripts/install-motion-template.sh"
echo "Installed $DESTINATION"
echo "Restart Final Cut Pro, then find OsmoReframe under 360."


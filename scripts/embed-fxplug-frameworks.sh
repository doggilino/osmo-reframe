#!/bin/bash
set -euo pipefail

FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
rm -rf "$FRAMEWORKS_DIR/FxPlug.framework" "$FRAMEWORKS_DIR/PluginManager.framework"
ditto --noacl --noextattr --noqtn --norsrc \
  /Library/Developer/Frameworks/FxPlug.framework "$FRAMEWORKS_DIR/FxPlug.framework"
ditto --noacl --noextattr --noqtn --norsrc \
  /Library/Developer/Frameworks/PluginManager.framework "$FRAMEWORKS_DIR/PluginManager.framework"
find "$FRAMEWORKS_DIR" -name Headers -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$FRAMEWORKS_DIR" -name '*.h' -delete 2>/dev/null || true
find "$FRAMEWORKS_DIR" -name '*.tbd' -delete 2>/dev/null || true
SIGNING_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/FxPlug.framework"
codesign --force --sign "$SIGNING_IDENTITY" "$FRAMEWORKS_DIR/PluginManager.framework"


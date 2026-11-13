#!/bin/bash
set -euo pipefail

PLUGINS_DIR="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Contents/PlugIns"
SOURCE="${BUILT_PRODUCTS_DIR}/OsmoReframeFxPlug.pluginkit"
DESTINATION="${PLUGINS_DIR}/OsmoReframeFxPlug.pluginkit"

mkdir -p "$PLUGINS_DIR"
rm -rf "$DESTINATION"
ditto "$SOURCE" "$DESTINATION"

# Xcode's generic XPC phase also creates a duplicate in Contents/XPCServices.
rm -rf "${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Contents/XPCServices"


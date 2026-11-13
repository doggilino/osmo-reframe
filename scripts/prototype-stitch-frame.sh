#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "usage: $0 input.OSV [output.jpg] [seconds]"
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="$1"
OUTPUT="${2:-$ROOT/build/prototypes/osmo-direct-proof.jpg}"
TIME="${3:-0}"
INPUT_FOV="${OSMO_INPUT_FOV:-190}"

if [[ ! -f "$INPUT" ]]; then
  echo "Input not found: $INPUT"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
ffmpeg -hide_banner -y \
  -ss "$TIME" \
  -i "$INPUT" \
  -filter_complex \
    "[0:v:0][0:v:1]hstack=inputs=2,v360=input=dfisheye:output=equirect:ih_fov=${INPUT_FOV}:iv_fov=${INPUT_FOV}:w=2048:h=1024:interp=lanczos[stitched]" \
  -map '[stitched]' \
  -frames:v 1 \
  -q:v 2 \
  "$OUTPUT"

echo "Created experimental stitched frame: $OUTPUT"

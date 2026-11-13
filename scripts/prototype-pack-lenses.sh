#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 4 ]]; then
  echo "usage: $0 input.OSV [output.mov] [seconds] [lens-size]"
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="$1"
OUTPUT="${2:-$ROOT/build/prototypes/osmo-dual-fisheye-proof.mov}"
DURATION="${3:-5}"
LENS_SIZE="${4:-1024}"

if [[ ! -f "$INPUT" ]]; then
  echo "Input not found: $INPUT"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

# This retains the two original lens projections instead of baking a stitch.
# OsmoReframe performs dual-fisheye projection and seam blending in Final Cut.
ffmpeg -hide_banner -y \
  -t "$DURATION" \
  -i "$INPUT" \
  -filter_complex \
    "[0:v:0]scale=${LENS_SIZE}:${LENS_SIZE}:flags=lanczos[left];[0:v:1]scale=${LENS_SIZE}:${LENS_SIZE}:flags=lanczos[right];[left][right]hstack=inputs=2,format=yuv422p10le[packed]" \
  -map "[packed]" \
  -map '0:a:0?' \
  -c:v prores_ks \
  -profile:v 3 \
  -c:a pcm_s16le \
  -movflags +faststart \
  "$OUTPUT"

echo "Created dual-fisheye mezzanine: $OUTPUT"

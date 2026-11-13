#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 5 ]]; then
  echo "usage: $0 input.OSV [output.mov] [seconds] [width] [height]"
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="$1"
OUTPUT="${2:-$ROOT/build/prototypes/osmo-direct-proof.mov}"
DURATION="${3:-5}"
WIDTH="${4:-2048}"
HEIGHT="${5:-1024}"
INPUT_FOV="${OSMO_INPUT_FOV:-190}"

if [[ ! -f "$INPUT" ]]; then
  echo "Input not found: $INPUT"
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"

# Experimental proof only. The two square HEVC tracks are packed as the
# side-by-side dual-fisheye layout expected by FFmpeg's v360 filter. DJI's
# proprietary per-camera calibration, seam blend and stabilization metadata
# are intentionally not approximated here.
ffmpeg -hide_banner -y \
  -t "$DURATION" \
  -i "$INPUT" \
  -filter_complex \
    "[0:v:0][0:v:1]hstack=inputs=2,v360=input=dfisheye:output=equirect:ih_fov=${INPUT_FOV}:iv_fov=${INPUT_FOV}:w=${WIDTH}:h=${HEIGHT}:interp=lanczos,format=yuv422p10le[stitched]" \
  -map "[stitched]" \
  -map '0:a:0?' \
  -c:v prores_ks \
  -profile:v 3 \
  -c:a pcm_s16le \
  -movflags +faststart \
  "$OUTPUT"

echo "Created experimental stitched clip: $OUTPUT"

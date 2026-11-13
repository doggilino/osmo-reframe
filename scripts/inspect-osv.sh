#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/clip.OSV" >&2
  exit 2
fi

FILE="$1"
if [[ ! -f "$FILE" ]]; then
  echo "File not found: $FILE" >&2
  exit 2
fi

ffprobe -v error \
  -show_entries \
format=filename,format_name,duration,size,bit_rate:stream=index,codec_name,codec_long_name,codec_type,codec_tag_string,width,height,pix_fmt,profile,r_frame_rate,avg_frame_rate,color_range,color_space,color_transfer,color_primaries,channels,sample_rate:stream_tags \
  -of json "$FILE"


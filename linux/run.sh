#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -f "$root/host/FSRCNN_X4_video" ]]; then chmod u+x "$root/host/FSRCNN_X4_video"; fi
if [[ ! -x "$root/host/FSRCNN_X4_video" || "$root/host/FSRCNN_X4_video.cpp" -nt "$root/host/FSRCNN_X4_video" ]]; then bash "$root/build.sh"; fi
out="$root/results/run_$(date +%Y%m%d_%H%M%S_%N)"
mkdir -p "$out"
exec "$root/host/FSRCNN_X4_video" --input "$root/data/lr" --weights "$root/model/X4"  --ffmpeg "${FFMPEG:-ffmpeg}" --mode pipeline --buffers 3 --threads 4 --fps 60  --output "$out/video.mp4" --csv "$out/frames.csv" --summary "$out/summary.json"  --snapshots "$out/snapshots" "$@"

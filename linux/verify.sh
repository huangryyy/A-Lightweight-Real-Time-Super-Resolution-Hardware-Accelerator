#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
case "${1:-files}" in
 files) cd "$root"; sha256sum -c SHA256SUMS ;;
 board) python3 "$root/verification/verify_board.py" --model "$root/model/X4" --output "$root/results/board_$(date +%s%N)" ;;
 pipeline) cd "$root/host"; python3 validate_pipeline.py --run "$root/results/validation_$(date +%s%N)" --input "$root/data/lr" --weights "$root/model/X4" --tools "${FFMPEG_TOOLS:-/usr/bin}" ;;
 *) echo 'Usage: bash verify.sh [files|board|pipeline]'; exit 1 ;;
esac

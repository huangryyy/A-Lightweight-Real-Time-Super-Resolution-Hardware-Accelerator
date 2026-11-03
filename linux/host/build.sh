#!/usr/bin/env bash
set -euo pipefail
src_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
g++ -O3 -std=c++17 -fopenmp -pthread -Wall -Wextra -Wno-unused-function \
    -Wno-missing-field-initializers -I "$src_dir/.." \
    "$src_dir/FSRCNN_X4_video.cpp" -o "$src_dir/FSRCNN_X4_video"
"$src_dir/FSRCNN_X4_video" --help

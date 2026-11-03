#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ "${1:-}" == --install-deps ]]; then
    sudo apt-get update
    sudo apt-get install -y build-essential python3 pciutils ffmpeg "linux-headers-$(uname -r)"
fi
for tool in g++ make python3 lspci ffmpeg ffprobe; do
    command -v "$tool" >/dev/null || { echo "Missing $tool; run: bash setup.sh --install-deps" >&2; exit 1; }
done
test -d "/lib/modules/$(uname -r)/build" || { echo 'Install matching linux-headers first' >&2; exit 1; }
bash "$root/verify.sh" files
bash "$root/build.sh"
bash "$root/scripts/build_driver.sh"
echo 'Build complete. Configure FPGA and load XDMA as described in README.md.'

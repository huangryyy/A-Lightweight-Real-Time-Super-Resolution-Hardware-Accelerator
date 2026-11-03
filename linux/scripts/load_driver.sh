#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test "$(id -u)" -eq 0 || { echo 'Run with sudo'; exit 1; }
test -n "${SUDO_USER:-}" || { echo 'Use sudo from your normal account'; exit 1; }
echo 1 > /sys/bus/pci/rescan
lspci -n -d 10ee:903f | grep -q . || { echo 'FPGA not enumerated'; exit 1; }
test -d /sys/module/xdma || insmod "$root/driver/xdma/xdma.ko"
for node in /dev/xdma0_h2c_0 /dev/xdma0_c2h_0 /dev/xdma0_user; do
 test -c "$node"; chown "$SUDO_USER" "$node"; chmod 0600 "$node"
done

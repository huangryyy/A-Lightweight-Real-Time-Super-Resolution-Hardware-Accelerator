#!/usr/bin/env bash
set -euo pipefail
test "$(id -u)" -eq 0 || { echo 'Run with sudo'; exit 1; }
if pgrep -x FSRCNN_X4_video >/dev/null; then echo 'Stop running inference first'; exit 1; fi
if test -d /sys/module/xdma; then rmmod xdma; fi
for dev in /sys/bus/pci/devices/*; do
 if [[ $(cat "$dev/vendor") == 0x10ee && $(cat "$dev/device") == 0x903f ]]; then echo 1 > "$dev/remove"; fi
done
echo 'Driver unloaded; PCIe endpoint removed. Now program via JTAG.'

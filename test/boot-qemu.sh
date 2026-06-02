#!/usr/bin/env bash
set -euo pipefail
QCOW="${1:-$HOME/Developer/build/out/computeros-0.1-qemu.qcow2}"
OVMF_CODE=/usr/share/edk2/ovmf/OVMF_CODE.fd
VARS=$(mktemp); cp /usr/share/edk2/ovmf/OVMF_VARS.fd "$VARS"
LOG=$(mktemp)
timeout 300 qemu-system-x86_64 \
  -machine q35 -m 2048 -smp 2 \
  -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$QCOW",if=virtio,format=qcow2 \
  -nographic -serial mon:stdio 2>&1 | tee "$LOG" || true
echo "---- wynik ----"
if grep -q 'COMPUTEROS_BOOT_OK' "$LOG"; then
  echo "PASS: boot sentinel widoczny"; exit 0
else
  echo "FAIL: brak COMPUTEROS_BOOT_OK (zobacz log: $LOG)"; exit 1
fi

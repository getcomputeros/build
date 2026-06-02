#!/usr/bin/env bash
set -euo pipefail
# Graficzne odpalenie obrazu w oknie QEMU (zobaczysz framebuffer console: "computeros login:").
# Login 0.1: root / computeros. Wyjście: zamknij okno albo Ctrl-a x w terminalu (serial).
QCOW="${1:-$HOME/Developer/build/out/computeros-0.1-qemu.qcow2}"
[ -f "$QCOW" ] || { echo "brak obrazu: $QCOW"; exit 1; }
VARS=$(mktemp); cp /usr/share/edk2/ovmf/OVMF_VARS.fd "$VARS"
echo ">> Okno QEMU się otworzy. Login: root / computeros"
exec qemu-system-x86_64 \
  -machine q35 -m 2048 -smp 2 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/ovmf/OVMF_CODE.fd \
  -drive if=pflash,format=raw,file="$VARS" \
  -drive file="$QCOW",if=virtio,format=qcow2 \
  -vga virtio -display gtk \
  -serial mon:stdio

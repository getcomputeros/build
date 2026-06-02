#!/usr/bin/env bash
set -euo pipefail
# Buduje obraz FAT ESP (esp.img) z systemd-boot + kernel + initramfs + loader entry.
# Args: ROOTFS (źródło systemd-bootx64.efi), VMLINUZ, INITRAMFS, IMG, ESP_MB, VERSION
build_esp() {
  local ROOTFS=$1 VMLINUZ=$2 INITRAMFS=$3 IMG=$4 ESP_MB=$5 VERSION=$6
  local EFI="$ROOTFS/usr/lib/systemd/boot/efi/systemd-bootx64.efi"
  [ -f "$EFI" ] || { echo "brak $EFI (systemd USE=boot gnuefi?)"; exit 1; }
  rm -f "$IMG"; truncate -s "${ESP_MB}M" "$IMG"
  mkfs.vfat -F32 -n COSESP "$IMG" >/dev/null
  # struktura katalogów w obrazie FAT (mtools, bez mount)
  mmd -i "$IMG" ::/EFI ::/EFI/BOOT ::/EFI/systemd ::/loader ::/loader/entries ::/computeros
  mcopy -i "$IMG" "$EFI" ::/EFI/BOOT/BOOTX64.EFI         # fallback path = autoboot bez efivars
  mcopy -i "$IMG" "$EFI" ::/EFI/systemd/systemd-bootx64.efi
  mcopy -i "$IMG" "$VMLINUZ"   ::/computeros/vmlinuz-${VERSION}
  mcopy -i "$IMG" "$INITRAMFS" ::/computeros/initramfs-${VERSION}.img
  # loader.conf
  printf 'default computeros-a\ntimeout 3\nconsole-mode max\n' > /tmp/loader.conf
  mcopy -i "$IMG" /tmp/loader.conf ::/loader/loader.conf
  # wpis bootowy (boot counting dojdzie w A/B; 0.1 = zwykły wpis)
  cat > /tmp/computeros-a.conf <<EOF
title    computerOS (slot A)
linux    /computeros/vmlinuz-${VERSION}
initrd   /computeros/initramfs-${VERSION}.img
options  cos.image=/images/rootfs-${VERSION}.squashfs console=tty0 console=ttyS0,115200
EOF
  mcopy -i "$IMG" /tmp/computeros-a.conf ::/loader/entries/computeros-a.conf
  echo "OK ESP: $IMG"
}

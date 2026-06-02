#!/usr/bin/env bash
set -euo pipefail
# Buduje system.img (ext4 z /images/rootfs.squashfs) i data.img (ext4 pusty),
# potem składa disk.raw: GPT (sgdisk) + dd każdej partycji na jej offset. Bez root/loop.

build_system_img() {  # SQUASHFS VERSION OUT_IMG SIZE_MB
  local SQUASHFS=$1 VERSION=$2 OUT=$3 MB=$4
  local STAGE; STAGE=$(mktemp -d); mkdir -p "$STAGE/images"
  cp "$SQUASHFS" "$STAGE/images/rootfs-${VERSION}.squashfs"
  rm -f "$OUT"; truncate -s "${MB}M" "$OUT"
  mkfs.ext4 -q -L cos-system -d "$STAGE" "$OUT"   # -d populuje BEZ mount
  rm -rf "$STAGE"; echo "OK system: $OUT"
}

build_data_img() {    # OUT_IMG SIZE_MB
  local OUT=$1 MB=$2
  rm -f "$OUT"; truncate -s "${MB}M" "$OUT"
  mkfs.ext4 -q -L cos-data "$OUT"
  echo "OK data: $OUT"
}

assemble_disk() {     # DISK ESP SYS DATA  (rozmiary wnioskowane z plików)
  local DISK=$1 ESP=$2 SYS=$3 DATA=$4
  local ALIGN=2048 SECT=512
  local esp_s sys_s data_s
  esp_s=$(( $(stat -c%s "$ESP")  / SECT ))
  sys_s=$(( $(stat -c%s "$SYS")  / SECT ))
  data_s=$(( $(stat -c%s "$DATA")/ SECT ))
  local esp_start=$ALIGN
  local sys_start=$(( ( (esp_start + esp_s + ALIGN -1)/ALIGN)*ALIGN ))
  local data_start=$(( ( (sys_start + sys_s + ALIGN -1)/ALIGN)*ALIGN ))
  local total=$(( data_start + data_s + ALIGN ))
  rm -f "$DISK"; truncate -s "$(( total*SECT ))" "$DISK"
  sgdisk -a "$ALIGN" \
    -n 1:${esp_start}:+$(( esp_s ))  -t 1:ef00 -c 1:ESP \
    -n 2:${sys_start}:+$(( sys_s ))  -t 2:8300 -c 2:system \
    -n 3:${data_start}:+$(( data_s )) -t 3:8300 -c 3:data \
    "$DISK"
  dd if="$ESP"  of="$DISK" bs=$SECT seek="$esp_start"  conv=notrunc status=none
  dd if="$SYS"  of="$DISK" bs=$SECT seek="$sys_start"  conv=notrunc status=none
  dd if="$DATA" of="$DISK" bs=$SECT seek="$data_start" conv=notrunc status=none
  sgdisk -p "$DISK"
}

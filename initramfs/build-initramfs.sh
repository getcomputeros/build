#!/usr/bin/env bash
set -euo pipefail
# JeOS initramfs: bash + util-linux (mount/losetup/switch_root/findfs) + ich biblioteki (ldd).
# Bez busybox → bez kaskady static-libs USE. Binarki i .so brane z /rootfs.
ROOTFS="${1:?podaj sciezke /rootfs}"
INIT="$(cd "$(dirname "$0")" && pwd)/init"
OUT="${2:?podaj plik wyjsciowy initramfs.img}"

WD=$(mktemp -d)
mkdir -p "$WD"/{bin,proc,sys,dev,mnt,etc}

# znajdź binarkę w /rootfs (różne dystrybucje kładą w bin/sbin/usr/...)
find_bin() {
  local n=$1
  for p in bin sbin usr/bin usr/sbin; do
    [ -x "$ROOTFS/$p/$n" ] && { echo "$ROOTFS/$p/$n"; return 0; }
  done
  echo "nie znaleziono $n w rootfs" >&2; return 1
}

copy_with_libs() {
  local src=$1
  install -Dm0755 "$src" "$WD/bin/$(basename "$src")"
  # ldd w kontenerze gentoo zwraca ścieżki .so; rootfs (to samo drzewo) ma je pod tym samym path.
  # Bez chroot/privileged. Kopiujemy interp + liby zachowując oryginalne ścieżki.
  ldd "$src" 2>/dev/null | awk '/=>/{print $3} /^\t\//{print $1}' | while read -r lib; do
    [ -n "$lib" ] || continue
    if   [ -f "$ROOTFS$lib" ]; then install -Dm0755 "$ROOTFS$lib" "$WD$lib"
    elif [ -f "$lib" ];        then install -Dm0755 "$lib"        "$WD$lib"
    fi
  done
}

# bash NIE ma wbudowanych mkdir/cat (to osobne binarki coreutils) — dokładamy je.
for b in bash mount losetup switch_root findfs mkdir cat; do
  copy_with_libs "$(find_bin "$b")"
done

install -m0755 "$INIT" "$WD/init"
( cd "$WD" && find . | cpio -o -H newc | gzip -9 ) > "$OUT"
rm -rf "$WD"
echo "OK: $OUT"

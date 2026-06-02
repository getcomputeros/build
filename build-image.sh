#!/usr/bin/env bash
set -euo pipefail
VERSION="0.1"

echo ">> Konfiguracja Portage: zamrożone drzewo gentoo (bez sync) + overlay computeros"
mkdir -p /etc/portage/repos.conf
# Drzewo gentoo = zamontowany frozen checkout; WYŁĄCZAMY auto-sync (reprodukowalność)
printf "[gentoo]\nlocation = /var/db/repos/gentoo\nauto-sync = no\nsync-type =\n" \
  > /etc/portage/repos.conf/gentoo.conf
printf "[computeros]\nlocation = /var/db/repos/computeros\nauto-sync = no\n" \
  > /etc/portage/repos.conf/computeros.conf
# Profil ustawiamy symlinkiem make.profile (pewne, nie wymaga profiles.desc/eselect)
ln -sfn /var/db/repos/computeros/profiles/computeros /etc/portage/make.profile

echo ">> Narzędzia hosta-buildera (NIE trafiają do obrazu)"
emerge -q1 sys-fs/squashfs-tools sys-apps/gptfdisk sys-fs/mtools sys-fs/dosfstools sys-fs/e2fsprogs app-arch/cpio

echo ">> Instalacja userlandu do /rootfs — kuratorowany set RUNTIME (--root-deps=rdeps)"
# NIE @system (ciągnie gcc/binutils/make/portage do obrazu). Tylko to czego JeOS potrzebuje
# do działania; --root-deps=rdeps → tylko RDEPEND ląduje w /rootfs, toolchain zostaje w kontenerze.
# computeros/core-runtime = nasz ebuild wyjmujący runtime .so z gcc (śledzony, w lock-manifeście).
emerge --root=/rootfs --root-deps=rdeps -q \
  sys-apps/systemd sys-apps/util-linux sys-apps/shadow app-shells/bash \
  sys-apps/baselayout sys-apps/coreutils sys-apps/kmod \
  computeros/core-runtime

echo ">> Odświeżenie cache linkera (core-runtime .so dodane przez ebuild)"
ldconfig -r /rootfs 2>/dev/null || true

echo ">> Lockfile/manifest paczek (dokładne wersje w obrazie) — przed cleanupem"
( cd /rootfs/var/db/pkg && ls -d */* ) | sort > "/out/lock-${VERSION}.txt"
echo "   $(wc -l < /out/lock-${VERSION}.txt) paczek zapisanych do lock-${VERSION}.txt"

echo ">> Tożsamość systemu (0.1: w builderze; docelowo ebuild branding)"
echo "computeros" > /rootfs/etc/hostname
# Pusty machine-id = systemd wygeneruje UNIKALNY przy pierwszym boocie (golden image, nie wypalamy
# jednego id dla wszystkich instalacji).
: > /rootfs/etc/machine-id
cat > /rootfs/etc/os-release <<EOF
NAME=computerOS
PRETTY_NAME="computerOS ${VERSION}"
ID=computeros
VERSION="${VERSION}"
EOF

echo ">> Hasło root (0.1: znane testowe 'computeros'; do usunięcia/zmiany w 0.4)"
# Domyślnie root jest ZABLOKOWANY (* w shadow) → bez tego nie zalogujesz się nigdzie.
# Puste hasło bywa odrzucane przez PAM (brak nullok), więc ustawiamy REALNE, znane.
echo 'root:computeros' | chpasswd --root /rootfs 2>/dev/null \
  || sed -i 's#^root:[^:]*:#root::#' /rootfs/etc/shadow   # fallback: puste

echo ">> Sentinel boot (unit drukujący na konsolę po starcie)"
cat > /rootfs/etc/systemd/system/cos-boot-ok.service <<'EOF'
[Unit]
Description=computerOS boot sentinel
After=multi-user.target
[Service]
Type=oneshot
StandardOutput=journal+console
ExecStart=/bin/sh -c 'echo COMPUTEROS_BOOT_OK'
[Install]
WantedBy=multi-user.target
EOF
ln -sf /etc/systemd/system/cos-boot-ok.service \
  /rootfs/etc/systemd/system/multi-user.target.wants/cos-boot-ok.service

echo ">> Autologin root na serialu (0.1: ułatwia weryfikację; do usunięcia w 0.4)"
mkdir -p /rootfs/etc/systemd/system/serial-getty@ttyS0.service.d
cat > /rootfs/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --autologin root --keep-baud 115200,57600,38400,9600 - $TERM
EOF

echo ">> Cleanup (mniejszy obraz)"
rm -rf /rootfs/usr/share/man/* /rootfs/usr/share/doc/* /rootfs/usr/share/locale/* \
       /rootfs/var/cache/* /rootfs/var/db/repos/* 2>/dev/null || true

echo ">> mksquashfs"
mksquashfs /rootfs "/out/rootfs-${VERSION}.squashfs" -comp zstd -all-root -noappend
ls -lh "/out/rootfs-${VERSION}.squashfs"

echo ">> Faza 2: kernel + initramfs + assembly"
source /build/lib/bootloader.sh
source /build/lib/partition.sh

BOARD="${BOARD:-qemu}"
VMLINUZ=$(ls /out/vmlinuz-*-"${BOARD}" 2>/dev/null | head -1)
[ -n "$VMLINUZ" ] || { echo "brak kernela dla board=$BOARD w /out (zbuduj: kernel/build-kernel.sh $BOARD)"; exit 1; }
echo "   kernel: $VMLINUZ (board=$BOARD)"
INITRAMFS="/out/initramfs-${VERSION}.img"
/build/initramfs/build-initramfs.sh /rootfs "$INITRAMFS"

build_esp        /rootfs "$VMLINUZ" "$INITRAMFS" /out/esp.img    512  "$VERSION"
build_system_img "/out/rootfs-${VERSION}.squashfs" "$VERSION" /out/system.img 4096
build_data_img   /out/data.img 2048
assemble_disk    /out/disk.raw /out/esp.img /out/system.img /out/data.img

# Konwersję raw->qcow2 robi HOST (run-local.sh) — qemu-img jest na Fedorze, nie budujemy qemu w stage3.
echo ">> GOTOWE (kontener): /out/disk.raw — host zrobi qcow2"

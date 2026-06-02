#!/usr/bin/env bash
set -euo pipefail
# Odpala build-image.sh w gentoo/stage3 z: ZAMROŻONYM drzewem gentoo (checkout na SHA, bez sync),
# overlayem computeros, i katalogiem wyjścia. To jest mechanizm wersjonowania — patrz release.toml.
ROOT="$(cd "$(dirname "$0")" && pwd)"
ENGINE="${ENGINE:-podman}"            # podman albo docker: `ENGINE=docker ./run-local.sh`
BOARD="${BOARD:-qemu}"                # qemu (0.1) | fat (boots anywhere) | <board>; `BOARD=fat ./run-local.sh`
# stage3 przypięty PO DIGEŚCIE (nie tag) — podmień na realny po `$ENGINE pull`:
STAGE3="docker.io/gentoo/stage3:amd64-systemd"   # TODO: zamień na ...@sha256:<digest>
GENTOO_SHA="$(awk -F'"' '/gentoo_repo_sha/{print $2}' "$ROOT/release.toml")"
OVERLAY="${OVERLAY:-$HOME/Developer/overlays/overlay-computeros}"
OUT="${OUT:-$ROOT/out}"; mkdir -p "$OUT"

# Zamrożone drzewo gentoo: cache na hoście, twardy checkout na SHA z release.toml. BEZ emerge --sync.
TREE="${TREE:-$HOME/.cache/computeros/gentoo-tree}"
[ -d "$TREE/.git" ] || git clone --filter=blob:none https://github.com/gentoo-mirror/gentoo "$TREE"
git -C "$TREE" fetch -q origin
git -C "$TREE" checkout -q "$GENTOO_SHA"
echo ">> drzewo gentoo zamrożone na $GENTOO_SHA (engine: $ENGINE)"

# :z na mountach = relabel SELinux (Fedora); działa i dla podman, i dla docker.
"$ENGINE" run --rm -it -e BOARD="$BOARD" \
  -v "$TREE":/var/db/repos/gentoo:ro,z \
  -v "$OVERLAY":/var/db/repos/computeros:ro,z \
  -v "$ROOT":/build:ro,z \
  -v "$OUT":/out:z \
  --tmpfs /rootfs:rw,size=4g \
  "$STAGE3" bash /build/build-image.sh

# Konwersja raw -> qcow2 na hoście (qemu-img z Fedory)
if [ -f "$OUT/disk.raw" ]; then
  qemu-img convert -f raw -O qcow2 "$OUT/disk.raw" "$OUT/computeros-0.1-${BOARD}.qcow2"
  echo ">> GOTOWE: $OUT/computeros-0.1-${BOARD}.qcow2"
fi

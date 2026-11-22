#!/usr/bin/env bash
# Install cactusctl into the Debian chroot (run as root).
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${CACTUS_PREFIX_DIR:-/opt/cactusctl}"
CONF_DIR="${CACTUS_CONF_DIR:-/etc/cactusctl}"
BIN_LINK="${CACTUS_BIN:-/usr/local/bin/cactusctl}"

[ "$(id -u)" -eq 0 ] || { echo "harus jalankan sebagai root" >&2; exit 1; }
[ -f "$REPO_DIR/bin/cactusctl" ] || { echo "repo tidak lengkap: $REPO_DIR/bin/cactusctl tidak ada" >&2; exit 1; }

echo "==> install ke $PREFIX"
mkdir -p "$PREFIX/lib" "$CONF_DIR"
install -m 755 "$REPO_DIR/bin/cactusctl" "$PREFIX/cactusctl"
for lib in common services system; do
  install -m 644 "$REPO_DIR/lib/$lib.sh" "$PREFIX/lib/$lib.sh"
done

echo "==> config"
for f in cactusctl.conf.example links.conf.example; do
  [ -f "$CONF_DIR/$f" ] || install -m 644 "$REPO_DIR/config/$f" "$CONF_DIR/$f"
done
[ -f "$CONF_DIR/cactusctl.conf" ] || cp "$CONF_DIR/cactusctl.conf.example" "$CONF_DIR/cactusctl.conf"
[ -f "$CONF_DIR/links.conf" ] || cp "$CONF_DIR/links.conf.example" "$CONF_DIR/links.conf"

echo "==> symlink $BIN_LINK"
ln -sfn "$PREFIX/cactusctl" "$BIN_LINK"

echo
echo "Selesai. Coba:"
echo "  cactusctl version"
echo "  cactusctl status"
echo "  cactusctl links edit"
echo
echo "Konfigurasi: $CONF_DIR"

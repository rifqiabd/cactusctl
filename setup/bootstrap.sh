#!/usr/bin/env bash
# Provisioning awal untuk chroot Debian baru. Idempoten, tidak menimpa config.
set -uo pipefail

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

CONF_DIR="${CACTUS_CONF_DIR:-/etc/cactusctl}"
LINKS_FILE="$CONF_DIR/links.conf"
OC2API_DIR="${OC2API_DIR:-/opt/oc2api}"
HERMES_DIR="${HERMES_DIR:-/opt/hermes}"

say() { printf '[%s] %s\n' "$1" "$2"; }
need() { command -v "$1" >/dev/null 2>&1; }

PKGS="curl ca-certificates python3 git tar"
MISSING=""
for c in $PKGS; do need "$c" || MISSING="$MISSING $c"; done

if [ -n "$MISSING" ]; then
  say "MISSING" "paket:$MISSING"
  [ "$CHECK" -eq 1 ] || { apt-get update -qq && apt-get install -y $PKGS; }
else
  say "OK" "paket dasar terpasang"
fi

for d in "$OC2API_DIR" "$HERMES_DIR" /run/sshd /var/log; do
  if [ -d "$d" ]; then say "OK" "$d"; else say "MISSING" "$d"; [ "$CHECK" -eq 1 ] || mkdir -p "$d"; fi
done

for f in "$OC2API_DIR/svc.sh" "$HERMES_DIR/svc.sh" "/usr/sbin/sshd"; do
  [ -e "$f" ] && say "OK" "$f" || say "MISSING" "$f"
done

if [ -f "$LINKS_FILE" ]; then
  say "OK" "$LINKS_FILE"
else
  say "MISSING" "$LINKS_FILE (jalankan setup/install.sh dulu)"
fi

if need adb; then say "OK" "adb bridge"; else say "INFO" "adb belum ada: apt install adb"; fi

echo
if [ "$CHECK" -eq 1 ]; then
  echo "Mode check selesai. Tidak ada perubahan yang dibuat."
else
  echo "Provisioning selesai. Lanjut: cactusctl status"
fi

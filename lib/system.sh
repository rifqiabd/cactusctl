# cactusctl - system, network, update and configuration functions

# ---------- Android-side bridge (optional adb over TCP) ----------
android_connect() {
  cmd_exists "$ADB_BIN" || { warn "adb belum ada: apt install adb"; return 1; }
  if "$ADB_BIN" -s "$ADB_SERIAL" get-state >/dev/null 2>&1; then
    return 0
  fi
  "$ADB_BIN" connect "$ADB_SERIAL" >/dev/null 2>&1 || true
  if ! "$ADB_BIN" -s "$ADB_SERIAL" get-state >/dev/null 2>&1; then
    warn "adb belum authorize ke $ADB_SERIAL"
    info "coba: adb connect $ADB_SERIAL"
    info "atau salin adbkey/adbkey.pub yang sudah di-authorize ke /root/.android/"
    return 1
  fi
  return 0
}

android_exec() {
  local cmd="$*"
  if ! cmd_exists "$ADB_BIN"; then
    warn "akses sisi Android butuh adb di chroot: apt install adb"
    info "perintah setara: su -c \"$cmd\""
    return 1
  fi
  android_connect || return 1
  "$ADB_BIN" -s "$ADB_SERIAL" shell "su -c \"$cmd\"" 2>&1
}

cmd_android() {
  case "${1:-status}" in
    connect)
      android_connect && ok "terhubung ke $ADB_SERIAL" ;;
    status) android_exec "getprop ro.product.model; getprop ro.build.version.release; uptime" ;;
    battery) android_exec "dumpsys battery | grep -E 'level|status|temperature'" ;;
    shell) shift; android_exec "$*" ;;
    sshd) android_exec "service check activity" ;;
    *) err "usage: cactusctl android {connect|status|battery|shell <cmd>|sshd}"; exit 1;;
  esac
}

cmd_reboot() {
  confirm "Reboot perangkat sekarang?" || { info "dibatalkan"; return 0; }
  info "mengirim reboot ..."
  android_exec "reboot" || warn "gagal via adb, pakai: adb shell reboot"
}

cmd_ssh() {
  local act="${1:-status}"
  local pid
  pid=$(read_pidfile /run/sshd.pid 2>/dev/null) || pid=""
  case "$act" in
    status)
      if pid_alive "$pid"; then status_line "sshd (chroot)" "${C_GREEN}UP${C_RESET}  pid=$pid  port=22"
      else status_line "sshd (chroot)" "${C_RED}DOWN${C_RESET}"; fi
      ;;
    start|stop|restart)
      case "$act" in
        restart) cmd_ssh stop; cmd_ssh start ;;
        start)
          mkdir -p /run/sshd
          /usr/sbin/sshd -E /var/log/sshd.log && ok "sshd started"
          ;;
        stop) [ -n "$pid" ] && kill "$pid" && ok "sshd stopped ($pid)" || info "sshd tidak jalan" ;;
      esac
      ;;
    *) err "usage: cactusctl ssh {status|start|stop|restart}"; exit 1;;
  esac
}

cmd_tailscale() {
  case "${1:-status}" in
    status)
      local p; p=$(proc_find 'tailscale' | head -1)
      if [ -n "$p" ]; then status_line "tailscale" "${C_GREEN}UP${C_RESET}  pid=$p"; else status_line "tailscale" "${C_RED}DOWN${C_RESET}"; fi
      ;;
    fix) android_exec "am start -n com.tailscale.ipn/.MainActivity" ;;
    *) err "usage: cactusctl tailscale {status|fix}"; exit 1;;
  esac
}

# ---------- dashboard ----------
cmd_status() {
  head2 "cactusctl status"
  printf '  %-18s %s\n' "host" "$(hostname)  ($(uname -m))"
  printf '  %-18s %s\n' "uptime" "$(awk '{printf "%d hari, %d jam", int($1/86400), int(($1%86400)/3600)}' /proc/uptime 2>/dev/null)"

  oc2api_summary
  hermes_summary
  tunnel_summary

  local w; w=$(proc_find 'oc2api-watch.sh')
  [ -n "$w" ] && status_line "watchdog" "${C_GREEN}UP${C_RESET}  pid=$(echo $w)" || status_line "watchdog" "${C_RED}DOWN${C_RESET}"

  cmd_ssh status
  cmd_tailscale status

  head2 "resource"
  local mem; mem=$(awk '/MemAvailable/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
  status_line "mem available" "${mem:-?} MB"
  status_line "disk /" "$(df -h / 2>/dev/null | awk 'NR==2{print $4" free / "$2" total"}')"
  if is_mounted /mnt/sdlinux; then status_line "sd-linux" "${C_GREEN}mounted${C_RESET}"; else status_line "sd-linux" "${C_DIM}not mounted${C_RESET}"; fi
  if is_mounted /mnt/sdcard; then status_line "sdcard" "${C_GREEN}mounted${C_RESET}"; fi

  head2 "public"
  local pub; pub=$(http_status "$PUBLIC_URL/healthz" 10)
  local col="$C_GREEN"; [ "$pub" = "200" ] || col="$C_YELLOW"
  status_line "$PUBLIC_URL" "${col}${pub}${C_RESET}"
  echo
}

cmd_info() {
  head2 "device info"
  android_exec "getprop ro.product.model; getprop ro.build.version.release; getprop ro.product.cpu.abi; cat /proc/uptime" \
    || info "(bridge Android tidak aktif — menampilkan info chroot)"
  printf '  %-18s %s\n' "kernel" "$(uname -r)"
  printf '  %-18s %s\n' "distro" "$(. /etc/os-release 2>/dev/null; echo ${PRETTY_NAME:-unknown})"
  printf '  %-18s %s\n' "python" "$(python3 -V 2>&1)"
}

cmd_disk() {
  head2 "disk"
  df -h 2>/dev/null | grep -vE 'tmpfs|devtmpfs' || true
  head2 "dirs"
  for d in /opt/oc2api /opt/hermes /root; do
    printf '  %-24s %s\n' "$d" "$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
  done
}

cmd_net() {
  head2 "endpoints"
  status_line "local health" "$(http_status "$API_URL/healthz")"
  status_line "local models" "$(http_status "$API_URL/v1/models")"
  status_line "public health" "$(http_status "$PUBLIC_URL/healthz" 15)"
  status_line "public models" "$(http_status "$PUBLIC_URL/v1/models" 15)"
}

# ---------- config / links ----------
cmd_config() {
  case "${1:-path}" in
    path) printf '%s\n' "$CONF_FILE" ;;
    show)
      printf '%s\n' "CONF_FILE=$CONF_FILE" "LINKS_FILE=$LINKS_FILE"
      printf '%s\n' "OC2API_DIR=$OC2API_DIR" "HERMES_DIR=$HERMES_DIR"
      printf '%s\n' "API_URL=$API_URL" "PUBLIC_URL=$PUBLIC_URL"
      printf '%s\n' "LOCAL_KEY=$(mask "$LOCAL_KEY")"
      ;;
    edit) "${EDITOR:-vi}" "$CONF_FILE" ;;
    reload) load_config; ok "config dimuat ulang" ;;
    *) err "usage: cactusctl config {path|show|edit|reload}"; exit 1;;
  esac
}

cmd_links() {
  case "${1:-show}" in
    show) [ -f "$LINKS_FILE" ] && cat "$LINKS_FILE" || { warn "belum ada $LINKS_FILE"; info "contoh: $CACTUS_PREFIX_DIR/config/links.conf.example"; } ;;
    edit) "${EDITOR:-vi}" "$LINKS_FILE" ;;
    *) err "usage: cactusctl links {show|edit}"; exit 1;;
  esac
}

# ---------- update engine ----------
resolve_oc2api_asset() {
  # Prints "url sha_url" resolved from GitHub API if OC2API_URL empty.
  if [ -n "${OC2API_URL:-}" ]; then
    printf '%s %s\n' "$OC2API_URL" "${OC2API_SHA_URL:-}"
    return 0
  fi
  need_cmd curl
  local repo="${OC2API_REPO:-jasonxu114514/opencode2api}"
  local api="https://api.github.com/repos/$repo/releases"
  local tag="${OC2API_VERSION:-latest}"
  local js
  if [ "$tag" = "latest" ]; then
    js=$(curl -fsSL --max-time 25 "$api/latest" 2>/dev/null) || die "gagal query GitHub releases"
  else
    js=$(curl -fsSL --max-time 25 "$api/tags/$tag" 2>/dev/null) || die "gagal query GitHub release $tag"
  fi
  printf '%s\n' "$js" | python3 - <<'PY' || die "tidak ada aset linux_arm64"
import json,sys
d=json.load(sys.stdin)
a=[x for x in d.get('assets',[]) if x['name'].endswith('linux_arm64.tar.gz')]
s=[x for x in d.get('assets',[]) if x['name'].endswith('linux_arm64.tar.gz.sha256')]
if not a: sys.exit(1)
print(a[0]['browser_download_url'], s[0]['browser_download_url'] if s else '')
PY
}

update_oc2api() {
  need_cmd curl tar
  info "mencari aset oc2api ..."
  read -r url shaurl <<<"$(resolve_oc2api_asset)"
  [ -n "${url:-}" ] || die "URL tidak teresolusi — isi OC2API_URL di $LINKS_FILE"
  info "download: $url"
  local tmp; tmp=$(mktemp -d)
  curl -fSL --max-time 180 -o "$tmp/pkg.tar.gz" "$url" || die "download gagal"
  if [ -n "${shaurl:-}" ]; then
    curl -fsSL --max-time 30 -o "$tmp/pkg.sha256" "$shaurl" 2>/dev/null || true
    if [ -f "$tmp/pkg.sha256" ]; then
      local want got
      want=$(awk '{print $1}' "$tmp/pkg.sha256" | head -1)
      got=$(python3 -c "import hashlib;print(hashlib.sha256(open('$tmp/pkg.tar.gz','rb').read()).hexdigest())")
      [ "$want" = "$got" ] || die "sha256 tidak cocok"
      ok "sha256 OK"
    fi
  fi
  tar -xzf "$tmp/pkg.tar.gz" -C "$tmp"
  local bin; bin=$(find "$tmp" -type f -name opencode2api -perm -u+x | head -1)
  [ -n "$bin" ] || die "binary opencode2api tidak ditemukan di paket"

  local stamp; stamp=$(date +%Y%m%d%H%M%S)
  cp -f "$OC2API_DIR/opencode2api" "$OC2API_DIR/opencode2api.bak.$stamp"
  install -m 755 "$bin" "$OC2API_DIR/opencode2api"
  ok "binary terpasang, backup: opencode2api.bak.$stamp"

  info "restart gateway ..."
  "$OC2API_SVC" restart gateway >/tmp/cactus-update-restart.log 2>&1 || true
  local i=0 ready=0
  while [ "$i" -lt 30 ]; do
    if [ "$(http_status "$API_URL/healthz")" = "200" ]; then
      local st; st=$(oc2api_health_json | python3 -c 'import sys,json;print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)
      [ "$st" = "ok" ] && { ready=1; break; }
    fi
    i=$((i+1)); sleep 5
  done
  if [ "$ready" -eq 1 ]; then
    ok "update sukses: $(oc2api_health_json | python3 -c 'import sys,json;print(json.load(sys.stdin).get("version","?"))')"
    rm -rf "$tmp"
  else
    warn "health belum pulih — rollback ..."
    cp -f "$OC2API_DIR/opencode2api.bak.$stamp" "$OC2API_DIR/opencode2api"
    "$OC2API_SVC" restart gateway >/dev/null 2>&1 || true
    rm -rf "$tmp"
    die "update gagal, binary dikembalikan ke versi sebelumnya"
  fi
}

update_self() {
  need_cmd curl
  [ -n "${CACTUSCTL_URL:-}" ] || die "CACTUSCTL_URL belum diisi di $LINKS_FILE"
  local tmp; tmp=$(mktemp -d)
  info "download cactusctl ..."
  curl -fSL --max-time 120 -o "$tmp/cactusctl.pkg" "$CACTUSCTL_URL" || die "download gagal"
  case "$CACTUSCTL_URL" in
    *.tar.gz|*.tgz)
      tar -xzf "$tmp/cactusctl.pkg" -C "$tmp"
      local src; src=$(find "$tmp" -type f -name cactusctl | head -1)
      [ -n "$src" ] || die "file cactusctl tidak ada di paket"
      install -m 755 "$src" "${CACTUS_BIN:-/usr/local/bin/cactusctl}"
      ;;
    *) install -m 755 "$tmp/cactusctl.pkg" "${CACTUS_BIN:-/usr/local/bin/cactusctl}" ;;
  esac
  ok "cactusctl ter-update"
  rm -rf "$tmp"
}

cmd_update() {
  case "${1:-list}" in
    oc2api|all) update_oc2api; [ "${1:-}" = "all" ] && { info "self update dilewati (butuh CACTUSCTL_URL)"; } ;;
    self) update_self ;;
    check)
      info "versi terpasang: $(oc2api_health_json | python3 -c 'import sys,json;print(json.load(sys.stdin).get("version","?"))' 2>/dev/null)"
      [ -n "${OC2API_URL:-}" ] && info "URL kustom: $OC2API_URL" || info "URL: GitHub latest (${OC2API_REPO:-jasonxu114514/opencode2api})"
      ;;
    list)
      printf '  %-12s %s\n' "oc2api"  "cactusctl update oc2api"
      printf '  %-12s %s\n' "self"   "cactusctl update self"
      printf '  %-12s %s\n' "check"  "cactusctl update check"
      ;;
    *) err "usage: cactusctl update {check|oc2api|self|list}"; exit 1;;
  esac
}

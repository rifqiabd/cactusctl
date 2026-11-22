# cactusctl - Android UI headless mode (disable/enable UI packages via ADB bridge)

# Paket "aman": matikan tidak memicu RescueParty.
HEADLESS_SAFE_PKGS="com.dvil.tui_renewed com.android.launcher3"
# Paket "riskan": SystemUI. Mematikannya pernah memicu reboot RescueParty di device ini.
HEADLESS_RISK_PKGS="com.android.systemui"
HEADLESS_PKGS="$HEADLESS_SAFE_PKGS $HEADLESS_RISK_PKGS"
HEADLESS_PKGS_REVERSE="com.android.systemui com.android.launcher3 com.dvil.tui_renewed"

_headless_mem() {
  awk '/MemAvailable/{printf "%d MB", $2/1024}' /proc/meminfo 2>/dev/null || printf '?'
}

_headless_swap() {
  awk '/SwapFree/{printf "%d MB", $2/1024}' /proc/meminfo 2>/dev/null || printf '?'
}

_headless_pkg_state() {
  # echo: disabled | enabled | unknown
  local p="$1" out
  out=$(android_exec "pm list packages -d $p" 2>/dev/null) || { printf 'unknown'; return; }
  case "$out" in *"$p"*) printf 'disabled';; *) printf 'enabled';; esac
}

_headless_marker() {
  local m
  m=$(android_exec 'test -f /data/local/.server-mode && echo on || echo off' 2>/dev/null) || printf '?'
  printf '%s' "${m:-?}"
}

_headless_services() {
  oc2api_summary
  hermes_summary
  tunnel_summary
  cmd_ssh status
}

headless_status() {
  head2 "headless status"
  if android_connect >/dev/null 2>&1; then
    local p
    for p in $HEADLESS_PKGS; do
      status_line "$p" "$(_headless_pkg_state "$p")"
    done
    status_line ".server-mode" "$(_headless_marker)"
  else
    warn "bridge Android tidak aktif — tidak bisa cek paket UI"
  fi

  head2 "memory"
  status_line "MemAvailable" "$(_headless_mem)"
  status_line "SwapFree" "$(_headless_swap)"

  head2 "services"
  _headless_services
  echo
}

headless_on() {
  head2 "headless on"
  android_connect >/dev/null 2>&1 || die "bridge Android tidak aktif (cactusctl android connect)"

  if [ "$(_headless_marker)" != "on" ]; then
    info "membuat marker /data/local/.server-mode (cegah reboot saat layar mati)"
    android_exec 'touch /data/local/.server-mode' >/dev/null 2>&1 || warn "gagal membuat marker"
  fi

  confirm "Matikan console launcher + Launcher3 (SystemUI dibiarakan)?" \
    || { info "dibatalkan"; return 0; }

  local p st
  for p in $HEADLESS_SAFE_PKGS; do
    st=$(_headless_pkg_state "$p")
    if [ "$st" = "disabled" ]; then
      info "$p sudah disabled — skip"
      continue
    fi
    info "disable-user --user 0 $p ..."
    android_exec "pm disable-user --user 0 $p" 2>&1 | tail -2
    info "tunggu 20 detik, ukur memori ..."
    sleep 20
    printf '  %-24s MemAvailable=%s\n' "$p" "$(_headless_mem)"
  done

  if [ "${HEADLESS_FULL:-0}" = "1" ]; then
    warn "HEADLESS_FULL=1: mematikan SystemUI bisa memicu reboot RescueParty di device ini"
    if confirm "Yakin tetap matikan SystemUI?"; then
      for p in $HEADLESS_RISK_PKGS; do
        st=$(_headless_pkg_state "$p")
        [ "$st" = "disabled" ] && { info "$p sudah disabled — skip"; continue; }
        info "disable-user --user 0 $p ..."
        android_exec "pm disable-user --user 0 $p" 2>&1 | tail -2
        sleep 20
        printf '  %-24s MemAvailable=%s\n' "$p" "$(_headless_mem)"
      done
    else
      info "SystemUI dibiarakan"
    fi
  else
    info "SystemUI sengaja tidak dimatikan (aman dari RescueParty)."
    info "Kalau tetap mau: HEADLESS_FULL=1 cactusctl headless on"
  fi

  ok "mode headless diterapkan"
  head2 "verifikasi"
  echo "  cactusctl headless status"
  echo "  cactusctl status"
  echo "  cactusctl hermes status"
  echo "  Rollback: cactusctl headless off"
}

headless_off() {
  head2 "headless off"
  android_connect >/dev/null 2>&1 || die "bridge Android tidak aktif (cactusctl android connect)"

  confirm "Aktifkan kembali semua paket UI Android?" \
    || { info "dibatalkan"; return 0; }

  local p
  for p in $HEADLESS_PKGS_REVERSE; do
    info "enable $p ..."
    android_exec "pm enable $p" 2>&1 | tail -2
    sleep 5
  done

  ok "UI diaktifkan kembali"
  head2 "verifikasi"
  echo "  cactusctl headless status"
  echo "  cactusctl status"
  echo "  Nav/recents mungkin perlu: cactusctl oc2api restart"
}

cmd_headless() {
  case "${1:-status}" in
    status) headless_status ;;
    on)     headless_on ;;
    off)    headless_off ;;
    *) err "usage: cactusctl headless {status|on|off}"; exit 1;;
  esac
}

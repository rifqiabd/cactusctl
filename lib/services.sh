# cactusctl - service control functions

OC2API_SVC="$OC2API_DIR/svc.sh"
HERMES_SVC="$HERMES_DIR/svc.sh"

# ---------- oc2api ----------
oc2api_pid() {
  local p
  p=$(read_pidfile "$OC2API_DIR/gateway.pid" 2>/dev/null) || p=""
  if [ -n "$p" ] && pid_alive "$p"; then
    case "$(proc_cmdline "$p" 2>/dev/null)" in *opencode2api*) printf '%s\n' "$p"; return 0;; esac
  fi
  proc_find 'opencode2api -config' | head -1
}

oc2api_health_json() { curl -s --max-time 8 "$API_URL/healthz" 2>/dev/null; }

oc2api_summary() {
  local j pid
  pid=$(oc2api_pid)
  if [ -z "$pid" ]; then
    status_line "opencode2api" "${C_RED}DOWN${C_RESET}"
    return
  fi
  j=$(oc2api_health_json)
  local status version exposed total
  status=$(printf '%s' "$j" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("status","?"))' 2>/dev/null || echo '?')
  version=$(printf '%s' "$j" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("version","?"))' 2>/dev/null || echo '?')
  exposed=$(printf '%s' "$j" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("models",{}).get("exposed","?"))' 2>/dev/null || echo '?')
  total=$(printf '%s' "$j" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("models",{}).get("total","?"))' 2>/dev/null || echo '?')
  local col="$C_GREEN"
  [ "$status" = "ok" ] || col="$C_YELLOW"
  status_line "opencode2api" "${col}${status:-?}${C_RESET}  pid=$pid  ver=$version  models=$exposed/$total"
}

cmd_oc2api() {
  local act="${1:-status}"
  case "$act" in
    start|stop|restart|status)
      [ -x "$OC2API_SVC" ] || die "tidak ada $OC2API_SVC"
      "$OC2API_SVC" "$act" gateway
      ;;
    health)
      oc2api_health_json | python3 -m json.tool 2>/dev/null || oc2api_health_json
      ;;
    models)
      curl -s --max-time 12 -H "Authorization: Bearer $LOCAL_KEY" "$API_URL/v1/models" \
        | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(m["id"]) for m in d.get("data",[])]' 2>/dev/null \
        || err "gagal mengambil daftar model (cek LOCAL_KEY)"
      ;;
    test)
      local model="${2:-big-pickle}"
      info "chat test via $model ..."
      curl -s --max-time 90 -w '\nhttp=%{http_code} time=%{time_total}s\n' \
        -H "Authorization: Bearer $LOCAL_KEY" -H 'content-type: application/json' \
        -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"say hi in 3 words\"}],\"stream\":false}" \
        "$API_URL/v1/chat/completions" | head -c 900
      echo
      ;;
    config)
      [ -f "$OC2API_CONFIG" ] || die "tidak ada $OC2API_CONFIG"
      python3 - "$OC2API_CONFIG" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
def redact(o,k=''):
    if isinstance(o,dict):
        for a,b in o.items(): redact(b,a)
    elif isinstance(o,list):
        for b in o: redact(b,k)
    else:
        if any(s in k.lower() for s in ('key','token','secret','password','hash')): print(f'{k} = ***')
        else: print(f'{k} = {str(o)[:120]}')
redact(d)
PY
      ;;
    logs) cmd_logs oc2api "${2:-$LOG_LINES}" ;;
    *) err "usage: cactusctl oc2api {start|stop|restart|status|health|models|test|config|logs}"; exit 1;;
  esac
}

# ---------- hermes ----------
hermes_pid() {
  local p
  p=$(read_pidfile "$HERMES_DIR/gateway.pid" 2>/dev/null) || p=""
  if [ -n "$p" ] && pid_alive "$p"; then printf '%s\n' "$p"; return 0; fi
  proc_find 'hermes gateway run' | head -1
}

cmd_hermes() {
  local act="${1:-status}"
  [ -x "$HERMES_SVC" ] || die "tidak ada $HERMES_SVC"
  case "$act" in
    on|off|toggle)
      # honour the Android-side marker if bridge is available
      case "$act" in
        on)     rm -f /data/local/.hermes-off 2>/dev/null || true; "$HERMES_SVC" start ;;
        off)    touch /data/local/.hermes-off 2>/dev/null || true; "$HERMES_SVC" stop ;;
        toggle) if [ -f /data/local/.hermes-off ]; then rm -f /data/local/.hermes-off; "$HERMES_SVC" start; else touch /data/local/.hermes-off; "$HERMES_SVC" stop; fi ;;
      esac
      ;;
    start|stop|restart|status|check) "$HERMES_SVC" "$act" ;;
    logs) cmd_logs hermes "${2:-$LOG_LINES}" ;;
    *) err "usage: cactusctl hermes {on|off|toggle|start|stop|restart|status|logs}"; exit 1;;
  esac
}

hermes_summary() {
  local p; p=$(hermes_pid)
  if [ -n "$p" ]; then
    local marker=""
    [ -f /data/local/.hermes-off ] && marker=" ${C_YELLOW}(marker off)${C_RESET}"
    status_line "hermes" "${C_GREEN}UP${C_RESET}  pid=$p$marker"
  else
    status_line "hermes" "${C_RED}DOWN${C_RESET}"
  fi
}

# ---------- tunnel ----------
tunnel_pid() {
  local p
  p=$(read_pidfile "$OC2API_DIR/tunnel.pid" 2>/dev/null) || p=""
  if [ -n "$p" ] && pid_alive "$p"; then printf '%s\n' "$p"; return 0; fi
  proc_find 'cloudflared tunnel run' | head -1
}

cmd_tunnel() {
  local act="${1:-status}"
  case "$act" in
    start|stop|restart|status) "$OC2API_SVC" "$act" tunnel ;;
    logs) cmd_logs tunnel "${2:-$LOG_LINES}" ;;
    *) err "usage: cactusctl tunnel {start|stop|restart|status|logs}"; exit 1;;
  esac
}

tunnel_summary() {
  local p; p=$(tunnel_pid)
  if [ -n "$p" ]; then
    local pub; pub=$(http_status "$PUBLIC_URL/healthz" 10)
    local col="$C_GREEN"; [ "$pub" = "200" ] || col="$C_YELLOW"
    status_line "cloudflared" "${C_GREEN}UP${C_RESET}  pid=$p  public=${col}${pub}${C_RESET}"
  else
    status_line "cloudflared" "${C_RED}DOWN${C_RESET}"
  fi
}

# ---------- logs ----------
cmd_logs() {
  local svc="${1:-oc2api}" n="${2:-$LOG_LINES}" f
  case "$svc" in
    oc2api|gateway) f="$OC2API_DIR/run.log" ;;
    tunnel|cloudflared) f="$OC2API_DIR/named.log" ;;
    hermes) f="$HERMES_DIR/gateway.log" ;;
    sshd) f="/var/log/sshd.log" ;;
    *) die "log yang dikenal: oc2api|tunnel|hermes|sshd" ;;
  esac
  [ -f "$f" ] || die "tidak ada log: $f"
  printf '%s%s%s\n' "$C_DIM" "--- $f (tail -n $n) ---" "$C_RESET"
  tail -n "$n" "$f"
}

# ---------- watchdog / monitor / backup ----------
cmd_watchdog() {
  local act="${1:-status}"
  local pids; pids=$(proc_find 'oc2api-watch.sh')
  case "$act" in
    status)
      if [ -n "$pids" ]; then status_line "watchdog" "${C_GREEN}UP${C_RESET}  pid=$(echo $pids)"; else status_line "watchdog" "${C_RED}DOWN${C_RESET}"; fi
      ;;
    start|stop)
      warn "watchdog jalan di sisi Android. Jalankan: su -c 'sh $WATCHDOG_SCRIPT' (start) / pkill -f oc2api-watch.sh (stop)"
      [ "$act" = "start" ] && android_exec "setsid nohup sh $WATCHDOG_SCRIPT >/dev/null 2>&1 &"
      ;;
    *) err "usage: cactusctl watchdog {status|start|stop}"; exit 1;;
  esac
}

cmd_monitor() {
  local act="${1:-status}"
  case "$act" in
    run|now) android_exec "sh /data/adb/server-monitor.sh" ;;
    log) tail -n "${2:-$LOG_LINES}" /data/local/server-monitor.log 2>/dev/null || warn "log monitor tidak tersedia dari chroot" ;;
    status) warn "monitor dijalankan crond sisi Android (tiap 5 menit)" ;;
    *) err "usage: cactusctl monitor {run|log|status}"; exit 1;;
  esac
}

cmd_backup() {
  local act="${1:-list}"
  case "$act" in
    now) android_exec "sh /data/adb/server-backup.sh" ;;
    list) ls -lh /mnt/sdlinux/backups /data/local/backups 2>/dev/null || warn "belum ada direktori backup yang ter-mount di chroot" ;;
    *) err "usage: cactusctl backup {now|list}"; exit 1;;
  esac
}

# ---------- generic service dispatcher ----------
cmd_service() {
  local name="${1:-}" act="${2:-status}"
  case "$name" in
    oc2api|oc2|gateway) cmd_oc2api "$act" ;;
    hermes|hm) cmd_hermes "$act" ;;
    tunnel|cloudflared) cmd_tunnel "$act" ;;
    all)
      case "$act" in
        status) cmd_status ;;
        start)  cmd_oc2api start; cmd_tunnel start; cmd_hermes start ;;
        stop)   cmd_hermes stop; cmd_tunnel stop; cmd_oc2api stop ;;
        restart) cmd_tunnel restart; cmd_oc2api restart; cmd_hermes restart ;;
        *) err "aksi all: start|stop|restart|status"; exit 1;;
      esac
      ;;
    "") err "pilih service: oc2api|hermes|tunnel|all"; exit 1;;
    *) err "service tidak dikenal: $name"; exit 1;;
  esac
}

# cactusctl - shared helpers
# Sourced by bin/cactusctl. Do not execute directly.

# ---------- defaults (override in /etc/cactusctl/cactusctl.conf) ----------
CACTUS_APP="cactusctl"
CACTUS_VERSION="${CACTUS_VERSION:-1.0.0}"
CACTUS_PREFIX_DIR="${CACTUS_PREFIX_DIR:-/opt/cactusctl}"

OC2API_DIR="${OC2API_DIR:-/opt/oc2api}"
HERMES_DIR="${HERMES_DIR:-/opt/hermes}"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-$OC2API_DIR/cloudflared}"
OC2API_BIN="${OC2API_BIN:-$OC2API_DIR/opencode2api}"
OC2API_CONFIG="${OC2API_CONFIG:-$OC2API_DIR/config.json}"
HERMES_HOME_DIR="${HERMES_HOME_DIR:-/root/.hermes}"

API_URL="${API_URL:-http://127.0.0.1:8080}"
PUBLIC_URL="${PUBLIC_URL:-https://oc.thibbilqulub.my.id}"
LOCAL_KEY="${LOCAL_KEY:-}"

WATCHDOG_SCRIPT="${WATCHDOG_SCRIPT:-/data/adb/oc2api-watch.sh}"
ADB_SERIAL="${ADB_SERIAL:-127.0.0.1:5555}"
ADB_BIN="${ADB_BIN:-adb}"

LOG_LINES="${LOG_LINES:-40}"

CONF_DIR="${CACTUS_CONF_DIR:-/etc/cactusctl}"
CONF_FILE="$CONF_DIR/cactusctl.conf"
LINKS_FILE="$CONF_DIR/links.conf"

# ---------- colors ----------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RESET=$'\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_RESET=''
fi

ok()   { printf '%s[ok]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '%s[..]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }
head2() { printf '\n%s== %s ==%s\n' "$C_BOLD" "$*" "$C_RESET"; }

# ---------- config ----------
load_config() {
  [ -f "$CONF_FILE" ] && . "$CONF_FILE"
  [ -f "$LINKS_FILE" ] && . "$LINKS_FILE"
  if [ -z "$LOCAL_KEY" ] && [ -f "$OC2API_DIR/config.json" ]; then
    # server_keys are secret; only read the first one for API calls.
    LOCAL_KEY="$(python3 - "$OC2API_CONFIG" <<'PY' 2>/dev/null || true
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    keys=d.get('server_keys') or []
    print(keys[0] if keys else '')
except Exception:
    pass
PY
)"
  fi
}

# ---------- primitives ----------
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "butuh perintah: $1"; }
cmd_exists() { command -v "$1" >/dev/null 2>&1; }

pid_alive() { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }

read_pidfile() {
  [ -f "${1:-}" ] || return 1
  p=$(head -1 "$1" 2>/dev/null | tr -d '[:space:]')
  case "$p" in ''|*[!0-9]*) return 1;; esac
  printf '%s\n' "$p"
}

proc_cmdline() { [ -r "/proc/$1/cmdline" ] || return 1; tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null; }

proc_find() {
  # proc_find <substring>
  local d c
  for d in /proc/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    c=$(proc_cmdline "${d#/proc/}") || continue
    case "$c" in *"$1"*) printf '%s\n' "${d#/proc/}";; esac
  done
}

http_status() { curl -s -o /dev/null -w '%{http_code}' --max-time "${2:-8}" "$1" 2>/dev/null || echo 000; }

json_get() {
  # json_get <python-expression-on-d> [url|file]
  python3 - "$1" "${2:-}" <<'PY' 2>/dev/null || true
import json,sys
expr, src = sys.argv[1], sys.argv[2]
try:
    if src.startswith('http'):
        import urllib.request
        d=json.load(urllib.request.urlopen(src, timeout=8))
    else:
        d=json.load(open(src))
    print(eval(expr, {'d':d}))
except Exception:
    pass
PY
}

human_size() {
  local b=${1:-0}
  awk -v b="$b" 'BEGIN{split("B KB MB GB TB",u," ");i=1;while(b>=1024&&i<5){b/=1024;i++}printf "%.1f %s",b,u[i]}'
}

mask() {
  local s=${1:-}
  [ -z "$s" ] && { printf '(unset)'; return; }
  if [ ${#s} -gt 8 ]; then printf '%s…%s' "${s:0:4}" "${s: -3}"; else printf '***'; fi
}

status_line() { # label value
  printf '  %-18s %s\n' "$1" "$2"
}

is_mounted() { grep -q " $1 " /proc/mounts 2>/dev/null; }

confirm() {
  # confirm "prompt" -> 0 yes, 1 no
  [ -n "${YES:-}" ] && return 0
  printf '%s [y/N] ' "$1"
  read -r ans
  case "$ans" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

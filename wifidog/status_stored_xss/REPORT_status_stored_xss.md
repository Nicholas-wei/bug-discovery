# Unauthenticated `/wifidog/status` + stored XSS / info disclosure via attacker-controlled token

## Summary
WiFiDog exposes an administrative status endpoint at `/wifidog/status`. This endpoint is only protected by HTTP Basic authentication if `HTTPDUserName`/`HTTPDPassword` are configured. If they are not configured (common in minimal/default setups), any remote client can access `/wifidog/status`.

The status output includes client tokens (stored server-side from `/wifidog/auth?token=...`) and renders them into an HTML page without escaping. This allows a remote attacker to inject HTML/JS into the stored token field and have it execute in the browser of anyone viewing the status page (stored XSS). The status page also discloses sensitive client information (IP/MAC/token).

## Affected Code (Call Chain)
- Token ingestion:
  - `src/http.c:http_callback_auth()`
    - Reads `token` query variable and stores it in the client list (`client_list_add(..., token->value)`).
- Status rendering:
  - `src/http.c:http_callback_status()`
    - Only forces auth if `config->httpdusername` is set.
    - Calls `get_status_text()` and wraps it in HTML: `<pre>%s</pre>`
  - `src/wd_util.c:get_status_text()`
    - Prints `current->token` into the status text without escaping.
  - `src/http.c:send_http_page()` + `wifidog-msg.html`
    - Injects `$message` into HTML without escaping.

## Vulnerability Triggering Condition
1. `HTTPDUserName`/`HTTPDPassword` are not configured (so `/wifidog/status` is unauthenticated).
2. Attacker can cause a client entry to be created/updated with an attacker-controlled token string (via `/wifidog/auth?token=...`).
3. A victim views `/wifidog/status` in a browser.

## Root Cause
- Missing/optional authentication guarding an administrative endpoint.
- Lack of output encoding (HTML escaping) for attacker-controlled fields rendered into HTML.

## Minimal PoC

### PoC: End-to-end (via WiFiDog HTTP listener)
The repo includes an end-to-end PoC that:
- creates a client entry with a token containing a `<script>` marker, and
- fetches `/wifidog/status` and saves the response to disk.

Run:

```sh
poc_status_stored_xss.sh
```

Artifacts:
- Response: `poc/poc-status-stored-xss.response.html` (contains the injected `<script>` marker)
- Log: `poc/poc-status-stored-xss.log`
- Config used: `poc/wifidog-veth.conf` (sets up an environment where `arp_get()` can resolve MACs)

## Remedy / Fix Guidance
- **Always require authentication** for `/wifidog/status` (and other administrative endpoints), regardless of whether an auth user/pass is configured.
  - If the intent is “disabled unless configured,” then disable the endpoint entirely when credentials are missing.
- HTML-escape all dynamic fields in status output (tokens, IPs, MACs, hostnames, etc.) before embedding in HTML.
- Defense-in-depth:
  - avoid displaying tokens at all, or display a truncated/hash representation,
  - restrict the status listener to a management interface only.

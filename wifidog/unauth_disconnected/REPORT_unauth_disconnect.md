# Unauthenticated `/wifidog/disconnect` enables remote logout / DoS

## Summary
WiFiDog exposes a logout endpoint at `/wifidog/disconnect` that removes a client from the active client list if the request supplies a matching `mac` and `token`.

This endpoint is only protected by HTTP Basic authentication if `HTTPDUserName`/`HTTPDPassword` are configured. If they are not configured, any remote client can call `/wifidog/disconnect` and force logouts (denial of service) as long as they can obtain/guess a victim’s token and MAC address. In common configurations, `/wifidog/status` may also be unauthenticated and can disclose these values (see `REPORT_status_stored_xss.md`).

## Affected Code (Call Chain)
- `src/http.c:http_callback_disconnect()`
  - Only forces auth if `config->httpdusername` is set.
  - Accepts `token` and `mac` query variables.
  - Looks up the client by MAC and compares the stored token.
  - Calls `logout_client(client)` on match.

## Vulnerability Triggering Condition
1. `HTTPDUserName`/`HTTPDPassword` are not configured (so `/wifidog/disconnect` is unauthenticated).
2. Attacker sends a request to `/wifidog/disconnect` with:
   - `mac=<victim mac>`
   - `token=<victim token>`

## Root Cause
- The endpoint that performs a privileged action (disconnecting clients) is not protected unless optional HTTP basic auth is configured.
- Tokens/MACs may be obtainable via other endpoints or network observation, making forced logout feasible.

## Minimal PoC

### PoC: End-to-end (via WiFiDog HTTP listener)
The repo includes an end-to-end PoC that:
- creates a client entry, verifies that 1 client is connected,
- calls `/wifidog/disconnect` without HTTP auth, and
- verifies that the client count drops to 0.

Run:

```sh
poc_unauth_disconnect.sh
```

Evidence:
- Before: `poc/poc-unauth-disconnect.before.html` (shows `1 clients connected.`)
- After: `poc/poc-unauth-disconnect.after.html` (shows `0 clients connected.`)
- Log: `poc/poc-unauth-disconnect.log`

## Remedy / Fix Guidance
- Require authentication/authorization for `/wifidog/disconnect` unconditionally.
  - If credentials are not configured, disable the endpoint rather than leaving it open.
- Restrict management endpoints to a dedicated management interface or localhost-only binding.
- Defense-in-depth:
  - make tokens unguessable and avoid exposing them via status pages,
  - consider requiring POST + CSRF protection if a browser is expected to access the endpoint.

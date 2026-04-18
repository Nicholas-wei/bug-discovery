# Reflected HTML injection / XSS when auth server is unreachable

## Summary
When WiFiDog believes the auth server is unreachable, `http_callback_404()` serves an “apology” HTML page and includes a link back to the originally requested URL.

That URL (`tmp_url`) is constructed from attacker-controlled components (`Host:`, request path, query) and is embedded into HTML without escaping. Because the page is rendered through `send_http_page()` / `httpdOutput()` with no HTML encoding, a remote attacker can inject arbitrary HTML/JS (reflected XSS).

## Affected Code (Call Chain)
- `src/http.c:http_callback_404()`
  - Builds `tmp_url` using `r->request.host`, `r->request.path`, `r->request.query`
  - In the `!is_auth_online()` branch, builds HTML containing:
    - `<a href='%s'>...` with `%s = tmp_url`
  - Calls `send_http_page(r, ..., buf)`
- `src/http.c:send_http_page()`
  - Adds `message` variable and renders `config->htmlmsgfile` via `httpdOutput()`
- `wifidog-msg.html`
  - Injects `$message` directly into HTML (`<h2>$message</h2>`) with no escaping

## Vulnerability Triggering Condition
1. WiFiDog must enter the `!is_auth_online()` branch in `http_callback_404()` (e.g., auth server is down).
2. Attacker sends a request whose path and/or query contains characters that break out of the HTML attribute context (e.g., `'`).

## Root Cause
- `tmp_url` is attacker-influenced and is injected into HTML output without any HTML escaping/encoding.
- The templating mechanism (`httpdOutput()`) performs raw string substitution and does not escape variables.

## Minimal PoC

### PoC: End-to-end (via WiFiDog HTTP listener)
The repo includes an end-to-end PoC that:
- runs `src/wifidog` without starting an auth server (forcing the auth-down response), and
- sends a request with an injection payload in the path, and
- saves the raw HTTP response to disk.

Run:

```sh
poc_reflected_xss_authdown.sh
```

Expected result:
- `poc/poc-reflected-xss-authdown.response.html` contains the marker string `WIFIDOG_XSS_POC`.
- Log: `poc/poc-reflected-xss-authdown.log`

## Remedy / Fix Guidance
- HTML-escape attacker-controlled strings before embedding them into HTML (including attribute contexts).
  - At minimum, escape `& < > " '`.
- Avoid concatenating URLs into HTML templates as raw strings; use a templating approach that defaults to encoding.
- Consider returning a plain-text error response when backend services are down, or ensure the link target is safely encoded (e.g., percent-encode + HTML-escape).

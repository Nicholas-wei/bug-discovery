# Stack buffer overflow in `libhttpd` `httpdOutput()` (template variable expansion)

## Summary
`libhttpd/api.c:httpdOutput()` renders response bodies and performs simple `$var` substitutions by copying variable values into a fixed-size stack buffer `char buf[HTTP_MAX_LEN]`.

Due to incorrect accounting of how many bytes have been written after a substitution, `httpdOutput()` can write past the end of `buf`, leading to a stack-buffer-overflow. In WiFiDog, this is reachable during normal page rendering via `send_http_page()` and the HTML template (`wifidog-msg.html`).

## Affected Code (Call Chain)
- `src/http.c:send_http_page()`
  - Reads the HTML template (e.g. `wifidog-msg.html`)
  - Adds variables: `title`, `message`, `nodeID`
  - Calls `httpdOutput(r, buffer)`
- `libhttpd/api.c:httpdOutput(request *r, const char *msg)`
  - Builds output in a fixed `char buf[HTTP_MAX_LEN]`
  - Substitutes `$<varName>` with `curVar->value` using `strcpy(dest, curVar->value)`

## Vulnerability Triggering Condition
Trigger requires a template that performs multiple substitutions (or enough trailing template text after a large substitution) such that the total rendered output exceeds `HTTP_MAX_LEN` while `httpdOutput()` still believes it is within bounds.

In this repo, a minimal reliable trigger is achieved by a template containing many occurrences of `$message`.

## Root Cause
After a successful substitution, the code advances `dest` correctly but updates `count` incorrectly:

```c
strcpy(dest, curVar->value);
dest = dest + strlen(dest);
count += strlen(dest);   // BUG: strlen(dest) is 0 after dest has advanced
```

Because `count` is undercounted, the loop condition `count < HTTP_MAX_LEN` no longer prevents writes beyond the end of `buf`.

## Minimal PoC

### PoC: End-to-end (via WiFiDog HTTP listener)
The repo includes an end-to-end PoC that:
- runs `src/wifidog` under ASan, and
- uses a custom template and config to force repeated `$message` substitutions.

Run:

```sh
poc_httpdOutput_overflow.sh
```

Artifacts:
- Config: `poc/wifidog-loopback-repeat-message.conf`
- Template: `poc/wifidog-msg-repeat-message.html`
- Evidence log: `poc/poc-httpdoutput-overflow.log`

Expected result (ASan build):
- `AddressSanitizer: stack-buffer-overflow` in `libhttpd/api.c:httpdOutput()`.

## Remedy / Fix Guidance
- Fix the accounting bug:
  - update `count` by the number of bytes copied (e.g., `strlen(curVar->value)`), not `strlen(dest)` after advancing `dest`.
- Replace `strcpy()` with bounded copies and explicit remaining-capacity checks (or use `snprintf` with careful pointer arithmetic).
- Consider avoiding stack-sized `HTTP_MAX_LEN` buffers for templating entirely; stream output directly to the socket or use a dynamically sized buffer with a configured maximum.

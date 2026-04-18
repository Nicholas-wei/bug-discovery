# Off-by-one stack buffer overflow in `libhttpd` `_httpd_readLine()`

## Summary
`libhttpd` reads HTTP request lines/headers using `_httpd_readLine(request *r, char *destBuf, int len)`. If a line is exactly `len` bytes long (before the terminating `\n`), `_httpd_readLine()` writes the NUL terminator at `destBuf[len]`, which is one byte past the end of the destination buffer.

This is a remote-triggerable stack out-of-bounds write reachable through the WiFiDog HTTP listener.

## Affected Code (Call Chain)
- `libhttpd/api.c:httpdReadRequest(httpd *server, request *r)`
  - Allocates `char buf[HTTP_MAX_LEN];`
  - Calls `_httpd_readLine(r, buf, HTTP_MAX_LEN)` in a loop to read the request line and headers.
- `libhttpd/protocol.c:_httpd_readLine(request *r, char *destBuf, int len)`
  - Loops with `while (count < len) { ... *dst++ = curChar; count++; }`
  - After the loop: `*dst = 0;` (OOB when `count == len`)

## Vulnerability Triggering Condition
Send an HTTP request line (or header line) that is:
- exactly `HTTP_MAX_LEN` bytes long (default `10240`), and
- does not contain `\n` until *after* those `len` bytes.

## Root Cause
`_httpd_readLine()` allows writing `len` bytes into a `len`-byte buffer and then appends a terminator, requiring `len + 1` bytes of capacity. The loop should reserve space for the terminator (i.e., read at most `len - 1` bytes), or treat “line too long” as an error.

## Minimal PoC

### PoC: End-to-end (via WiFiDog HTTP listener)
The repo includes an end-to-end PoC that:
- runs `src/wifidog` with ASan enabled, and
- sends a crafted request line of length `HTTP_MAX_LEN` to trigger the overflow.

Run:

```sh
poc_readline_offbyone.sh
```

Expected result (ASan build):
- `poc/poc-readline-offbyone.log` contains `AddressSanitizer: stack-buffer-overflow` pointing into `libhttpd/protocol.c:_httpd_readLine()`.

## Remedy / Fix Guidance
- In `_httpd_readLine()`:
  - change the loop bound to `count < (len - 1)` and always terminate at `destBuf[count] = '\0'`, or
  - detect overlong lines and abort request parsing (e.g., return an error and close the connection).
- Treat unexpectedly long request lines/headers as malformed input (return HTTP 400 / close), rather than attempting to store them in a fixed buffer.

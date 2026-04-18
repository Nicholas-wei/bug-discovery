# Stack-buffer-overflow in `libhttpd` `_httpd_decode()` (Basic auth)

## Summary
WiFiDog embeds `libhttpd` as its HTTP listener. When parsing `Authorization: Basic ...`, `libhttpd/api.c:httpdReadRequest()` base64-decodes the attacker-controlled token into a fixed-size stack buffer (`authBuf[100]`). Due to incorrect output-size limiting in `libhttpd/protocol.c:_httpd_decode()`, a long `Authorization: Basic` token causes an out-of-bounds write past `authBuf`, leading to memory corruption (and a crash under AddressSanitizer).

## Affected Code (Call Chain)
- `libhttpd/api.c:httpdReadRequest()`
  - `char authBuf[100];`
  - `_httpd_decode(cp, authBuf, 100);`
- `libhttpd/protocol.c:_httpd_decode(char *bufcoded, char *bufplain, int outbufsize)`

## Vulnerability Triggering Condition
Send an HTTP request to the WiFiDog HTTP listener (default `GatewayPort` is `2060`) with:

- Header name: `Authorization`
- Scheme: `Basic`
- Token: at least **133** characters from the base64 alphabet (`A–Z`, `a–z`, `0–9`, `+`, `/`) before end-of-line

Minimal working example token: `"A" * 133`

### Why 133 is the minimal length
In `_httpd_decode()` the input length is bounded using:

```
nprbytes = (outbufsize * 4) / 3;
```

With `outbufsize = 100`, this yields `nprbytes = 133`.

Because `133` is **not a multiple of 4**, the decode loop:

```
while (nprbytes > 0) {
  *(bufout++) = ...
  *(bufout++) = ...
  *(bufout++) = ...
  nprbytes -= 4;
}
```

executes `ceil(133/4) = 34` iterations and writes `34 * 3 = 102` bytes into `authBuf[100]`, overflowing the destination.

Any base64 token length **≥ 133** triggers the issue in `httpdReadRequest()` because it forwards the token to `_httpd_decode()` with a 100-byte stack buffer.

## Root Cause
`_httpd_decode()` attempts to keep decoded output within `outbufsize`, but the bounding logic is incorrect:

1. **Wrong truncation unit:** it truncates the number of input base64 characters to `(outbufsize * 4) / 3` without rounding down to a multiple of 4. The decode loop emits 3 bytes for every 4 input chars, so a non-multiple-of-4 `nprbytes` causes an extra 3-byte write on the final iteration.
2. **No room for the terminator:** it treats `outbufsize` as “max decoded bytes”, but it always appends a NUL terminator (`bufplain[...] = 0`). A safe decoder must reserve one byte (`outbufsize - 1`) for the terminator.
3. **Stale `nbytesdecoded`:** it computes `nbytesdecoded` before truncating `nprbytes` and does not recompute it after truncation, yet uses `nbytesdecoded` as the index for NUL termination:

   ```
   bufplain[nbytesdecoded] = 0;
   ```

Together, these allow an attacker-controlled header to cause out-of-bounds writes on the stack.

## Minimal PoC

### PoC A: End-to-end (via WiFiDog HTTP listener)
The repo includes an end-to-end PoC script:

```sh
PAYLOAD_LEN=133 ./poc_basic_auth_overflow.sh
```

This runs WiFiDog in an unprivileged namespace and sends a crafted request with:

```
Authorization: Basic AAAAAAAAAA... (133 times)
```

Expected result (ASan build): `AddressSanitizer: stack-buffer-overflow` pointing to `authBuf` in `httpdReadRequest()` (see `poc/poc-basic-auth-overflow.log`).

### PoC B: Minimal direct call (decode-only)
```c
int _httpd_decode(char *in, char *out, int outsz);

int main(void) {
  char in[134];
  memset(in, 'A', 133);
  in[133] = '\0';

  char out[100];
  _httpd_decode(in, out, (int)sizeof(out));
  return 0;
}
```

## Remedy / Fix Guidance
Fix must be applied in `_httpd_decode()` (caller-side changes like passing `99` instead of `100` do **not** reliably fix the bug because the decoder uses a stale `nbytesdecoded` for termination).

Recommended properties of the fix:

- Treat `outbufsize` as total capacity **including** the NUL terminator.
- Never write more than `outbufsize - 1` decoded bytes.
- When bounding input, round `nprbytes` down to a multiple of 4.
- Recompute `nbytesdecoded` (or track bytes-written) based on the bounded input before writing the terminator.
- Prefer using a well-tested base64 decoder API that takes explicit input length + output capacity.

Defense-in-depth improvements (optional):

- In `httpdReadRequest()`, decode into a buffer at least as large as the destination fields (e.g. `HTTP_MAX_AUTH`) and reject/ignore overly long `Authorization` headers.


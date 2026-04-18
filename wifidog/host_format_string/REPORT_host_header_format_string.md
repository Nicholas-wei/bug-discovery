# Host header format string injection via `$ID$` gateway-id expansion

## Summary
WiFiDog expands a special `$ID$` token inside iptables command strings. The expansion is implemented by rewriting `$ID$` to a printf format specifier (`%1$s`) and then calling `safe_asprintf()` with the *entire command string* as the format string.

If an attacker can cause an iptables command string to include attacker-controlled text (e.g., via `Host:` in `fw_allow_host()`), they can inject additional `%...` format specifiers. This results in uncontrolled format parsing, which can crash the process and may enable memory disclosure and/or writes (e.g., `%n`) depending on platform/libc behavior.

## Affected Code (Call Chain)
- `src/http.c:http_callback_404()` → `fw_allow_host(r->request.host)` (whitelist-dependent)
- `src/firewall.c:fw_allow_host(const char *host)` → `iptables_fw_access_host(..., host)`
- `src/fw_iptables.c:iptables_fw_access_host(..., host)` → `iptables_do_command(..., host)`
- `src/fw_iptables.c:iptables_do_command(...)`
  - Builds a full command string `cmd`
  - Calls `iptables_insert_gateway_id(&cmd)`
- `src/fw_iptables.c:iptables_insert_gateway_id(char **input)`
  - Replaces `$ID$` with `%1$s` (in-place)
  - Calls `safe_asprintf(&buffer, *input, tmp_intf)` treating `*input` as a printf format string

## Vulnerability Triggering Condition
1. The request must reach a call to `fw_allow_host()` with attacker-controlled `Host:`.
2. The attacker-controlled string included in the resulting iptables command must contain `$ID$` and additional printf format specifiers (`%...`).
3. WiFiDog must execute the `$ID$` expansion (it runs for any iptables command containing `$ID$`).

## Root Cause
`iptables_insert_gateway_id()` treats untrusted command text as a printf format string:

- It transforms `$ID$` into a `%1$s` token.
- It then uses `safe_asprintf(&buffer, *input, tmp_intf)`, where `*input` is attacker-influenced.

This is a classic format-string injection pattern.

## Minimal PoC

### PoC: End-to-end (via WiFiDog HTTP listener)
The repo includes an end-to-end PoC that triggers an ASan-visible crash by sending a `Host:` header containing `$ID$` plus additional `%...` specifiers through the `fw_allow_host()` path.

Run:

```sh
poc_host_format_string.sh
```

Expected result:
- `poc/poc-host-format-string.log` contains an AddressSanitizer crash with a stack trace originating from `iptables_insert_gateway_id()` / `vasprintf()`.

## Remedy / Fix Guidance
- **Never use attacker-influenced strings as printf formats.**
  - Implement `$ID$` expansion as a literal string replacement (search/replace `$ID$` → `tmp_intf`) without any `printf`-style formatting.
  - Alternatively, use a fixed format string and pass the command as data: `safe_asprintf(&buffer, "%s", *input)` after performing a safe replacement.
- Harden any code paths that embed `Host:` into iptables commands:
  - validate `Host:` strictly,
  - reject `$ID$` in the `Host:` header entirely, and
  - avoid passing hostnames through a shell (see `REPORT_host_header_cmd_injection.md`).

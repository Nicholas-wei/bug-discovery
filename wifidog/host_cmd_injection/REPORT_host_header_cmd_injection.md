# Host header command injection via iptables rule update (RCE)

## Summary
WiFiDog dynamically updates firewall rules in response to some HTTP requests. In the `http_callback_404()` “allow (sub)domain again” path, the attacker-controlled `Host:` header is embedded into an iptables command string and executed via `/bin/sh -c`. This allows command injection and remote code execution as the WiFiDog process user (typically root).

## Affected Code (Call Chain)
- `src/http.c:http_callback_404()`
  - When online+auth-online, may call `fw_allow_host(r->request.host)` for certain whitelisted hosts/subdomains.
- `src/firewall.c:fw_allow_host(const char *host)`
  - Calls `iptables_fw_access_host(..., host)`.
- `src/fw_iptables.c:iptables_fw_access_host(fw_access_t type, const char *host)`
  - Builds commands like `iptables ... -d %s ...` with `host`.
- `src/fw_iptables.c:iptables_do_command(const char *format, ...)`
  - Builds a single command string (e.g. `"iptables -t nat -A ... -d <HOST> ..."`)
  - Calls `execute(cmd, quiet)`.
- `src/util.c:execute(const char *cmd_line, int quiet)`
  - Uses `execvp(WD_SHELL_PATH, ["sh","-c",cmd_line])`.

## Vulnerability Triggering Condition
1. The request must reach the `fw_allow_host()` callsite in `http_callback_404()`.
   - In practice, this depends on configuration (`FirewallRuleSet global`) and runtime state (WiFiDog believes internet+auth are reachable).
2. The attacker supplies a `Host:` header containing shell metacharacters.
3. WiFiDog executes an iptables command containing the untrusted `Host:` value via `/bin/sh -c`.

## Root Cause
- **Untrusted data is used to build a shell command string** (iptables invocation) without quoting or strict validation.
- The command string is executed via a shell (`/bin/sh -c`), which interprets metacharacters in `Host:` as additional shell syntax.

## Minimal PoC

### PoC: End-to-end (via WiFiDog HTTP listener)
The repository includes an end-to-end PoC that:
- runs `src/wifidog` (libtool wrapper) in an unprivileged user+net namespace, and
- sends a crafted HTTP request to the gateway HTTP port that reaches the vulnerable path, and
- creates a benign marker file to demonstrate command execution.

Run:

```sh
poc_host_cmd_injection.sh
```

Expected result:
- Marker file exists: `/tmp/wifidog_cmd_injection_pwned`
- Log file: `poc/poc-host-cmd-injection.log`

## Remedy / Fix Guidance
- **Do not invoke a shell** for iptables updates. Execute iptables with an argument vector (e.g. `execve("iptables", argv, envp)`), so `host` is treated as data.
- **Strictly validate the `Host:` header** before using it in firewall updates. At minimum, reject anything outside a conservative hostname character set (letters/digits/dot/hyphen) and enforce length limits.
- Consider resolving hostnames to IPs (with appropriate DNS-hardening) and only inserting validated IP literals into firewall rules.
- Defense-in-depth: ensure the “allow host again” flow can’t be reached based on attacker-provided `Host:` alone.

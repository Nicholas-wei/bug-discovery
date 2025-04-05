# totolink multiple device hard-coded telnet password

## Affected firmware info

Vendor: Totolink

Affected Firmware

Nr1800x

- nr1800x-v9.1.0u.6681_b20230703

Download website: https://www.totolink.net/home/news/me_name/id/39/menu_listtpl/DownloadC.html

## Description

totolink Nr1800x contains hard-coded telnet password, which allows any user to log into the telnet service of the device with root privilege.

## Detail


In binary `www/cgi-bin/cstecgi.cgi`, The following code controls the telnet service. The following code is at address `0x437D40`.

![image-20250212112119777](telnet_hardcode_passwd.assets/image-20250212112119777.png)

Form the code above, we can find that the password used for telnet service is from `nvram_safe_get("telnet_key_custom")`.

During initialization, the following code fills nvram with key `telnet_key_custom`. The following code is from `usr/sbin/custom_info_to_nvram` at address `0x401DD0`

![image-20250212112258959](telnet_hardcode_passwd.assets/image-20250212112258959.png)

An unauthenticated attacker can start and log into the telnet service by using key "KL@UHeZ0". 

## Timeline

[02/12/2025] report to cve
[05/04/25] assigned CVE-2025-27989